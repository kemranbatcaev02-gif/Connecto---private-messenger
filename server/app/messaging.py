"""Единый путь доставки сообщений: WebSocket, пуши, обновления для ботов."""
import json
import threading
import time
from collections import defaultdict
from datetime import datetime, timezone

from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from app.models.user import User
from app.models.chat import (Chat, ChatMember, Message, MessageReaction,
                             PushToken, BotUpdate)
from app.realtime import manager
from app.privacy import get_notify, is_premium, as_utc
from app.push import send_push

KIND_PREVIEW = {"image": "📷 Фото", "video": "🎬 Видео", "file": "📎 Файл",
                "voice": "🎤 Голосовое", "round": "📹 Видеосообщение",
                "location": "📍 Геолокация",
                "contact": "👤 Контакт", "gift": "🎁 Подарок"}


FREE_EFFECTS = {"confetti", "hearts", "fire", "snow", "balloons"}
PREMIUM_EFFECTS = {"fireworks", "money", "lightning", "rainbow", "stars", "sakura"}
TTL_VALUES = {0, 60, 3600, 86400, 604800}


def _now():
    return datetime.now(timezone.utc)


def is_sealed(msg: Message, viewer_id: str | None) -> bool:
    """Капсула времени ещё закрыта для этого зрителя."""
    if not msg.open_at or viewer_id == msg.sender_id:
        return False
    oa = as_utc(msg.open_at)
    return oa is not None and oa > _now()


def alive(q):
    """Фильтр: только не исчезнувшие сообщения."""
    from sqlalchemy import or_
    return q.filter(or_(Message.expires_at.is_(None), Message.expires_at > _now()))


def preview_text(msg: Message | None, viewer_id: str | None = None) -> str | None:
    if msg is None:
        return None
    if msg.open_at and is_sealed(msg, viewer_id):
        return "📦 Капсула времени"
    if msg.enc and msg.kind == "text":
        return "🔒 Сообщение"
    if msg.kind == "call":
        from app.calls import call_preview
        return call_preview(_extra(msg), viewer_id is not None and viewer_id == msg.sender_id)
    if msg.kind == "text" or msg.kind == "service":
        return msg.text
    return KIND_PREVIEW.get(msg.kind, msg.text or "Вложение")


def member_ids(db: Session, chat_id: str) -> list[str]:
    return [m.user_id for m in db.query(ChatMember).filter(ChatMember.chat_id == chat_id)]


def reactions_for(db: Session, msg_ids: list[str], viewer_id: str | None) -> dict:
    """msg_id → [{emoji, count, mine, user_ids}] (user_ids — первые 50)."""
    if not msg_ids:
        return {}
    out: dict = defaultdict(dict)
    rows = (db.query(MessageReaction).filter(MessageReaction.message_id.in_(msg_ids))
            .order_by(MessageReaction.created_at.asc()).all())
    for r in rows:
        slot = out[r.message_id].setdefault(
            r.emoji, {"emoji": r.emoji, "count": 0, "mine": False, "user_ids": []})
        slot["count"] += 1
        if len(slot["user_ids"]) < 50:
            slot["user_ids"].append(r.user_id)
        if r.user_id == viewer_id:
            slot["mine"] = True
    return {k: sorted(v.values(), key=lambda x: -x["count"]) for k, v in out.items()}


def message_dict(msg: Message, chat: Chat | None, sender: User | None,
                 reactions: list | None = None, forwarded_name: str | None = None,
                 viewer_id: str | None = None) -> dict:
    channel = chat is not None and chat.type == "channel"
    if channel:
        s_name = chat.title or "Канал"
        s_avatar = chat.avatar_url
    else:
        s_name = (sender.display_name or sender.username) if sender else "Удалённый аккаунт"
        s_avatar = sender.avatar_url if sender else None
    d = {
        "id": msg.id,
        "chat_id": msg.chat_id,
        "sender_id": msg.sender_id,
        "sender_name": s_name,
        "sender_avatar": s_avatar,
        "sender_frame": {"id": sender.avatar_frame, "url": f"/media/shop/{sender.avatar_frame}.png"} if (sender and getattr(sender, "avatar_frame", None) and not channel) else None,
        "sender_is_bot": bool(sender.is_bot) if sender else False,
        "sender_verified": bool(sender.is_verified) if sender else False,
        "sender_premium": is_premium(sender),
        "kind": msg.kind,
        "text": msg.text,
        "media_url": msg.media_url,
        "file_name": msg.file_name,
        "reply_to_id": msg.reply_to_id,
        "forwarded_from": msg.forwarded_from,
        "forwarded_name": forwarded_name,
        "edited": bool(msg.edited),
        "pinned": bool(msg.pinned),
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
        "reactions": reactions or [],
        "read": False,
        "effect": msg.effect,
        "silent": bool(msg.silent),
        "open_at": as_utc(msg.open_at).isoformat() if msg.open_at else None,
        "expires_at": as_utc(msg.expires_at).isoformat() if msg.expires_at else None,
        "sealed": False,
        "extra": _extra(msg),
        "enc": msg.enc,
    }
    if is_sealed(msg, viewer_id):
        d.update({"text": "", "media_url": None, "file_name": None, "sealed": True,
                  "reactions": [], "extra": None, "enc": None})
    return d


def _extra(msg: Message) -> dict | None:
    if not getattr(msg, "extra", None):
        return None
    try:
        v = json.loads(msg.extra)
        return v if isinstance(v, dict) else None
    except Exception:
        return None


def forwarded_name_of(db: Session, msg: Message) -> str | None:
    """Имя автора пересланного — если он разрешил ссылаться на себя."""
    if not msg.forwarded_from:
        return None
    from app.privacy import get_privacy
    u = db.query(User).filter(User.id == msg.forwarded_from).first()
    if u is None:
        return None
    if get_privacy(u).get("forwards") == "none":
        return "Скрытый пользователь"
    return u.display_name or u.username


def is_muted(member: ChatMember) -> bool:
    mu = member.muted_until or 0
    if mu == -1:
        return True
    return mu > int(time.time() * 1000)


# ── доставка ──

async def deliver(db: Session, chat: Chat, msg: Message, sender: User | None) -> dict:
    fwd = forwarded_name_of(db, msg)
    sender_id = sender.id if sender else None
    payload = message_dict(msg, chat, sender, [], fwd, viewer_id=sender_id)
    payload["type"] = "message"
    payload["chat_type"] = chat.type
    payload["chat_title"] = chat.title
    ids = member_ids(db, chat.id)
    if chat.is_system and sender is not None and sender.is_bot and not (
            msg.extra and '"support"' in msg.extra):
        # служебные уведомления Connecto (входы, почта…) админам-помощникам не шлём
        hidden = {m.user_id for m in db.query(ChatMember).filter(
            ChatMember.chat_id == chat.id, ChatMember.role == "support")}
        ids = [i for i in ids if i not in hidden]
    if msg.open_at and is_sealed(msg, None):
        # капсула: отправителю — полностью, остальным — запечатанную
        sealed = message_dict(msg, chat, sender, [], fwd, viewer_id=None)
        sealed.update({"type": "message", "chat_type": chat.type, "chat_title": chat.title})
        await manager.send_to_users([sender_id] if sender_id else [], payload)
        await manager.send_to_users([i for i in ids if i != sender_id], sealed)
    else:
        await manager.send_to_users(ids, payload)
    if not msg.silent and not _quiet_call(msg):
        try:
            await _push_offline(db, chat, msg, sender, ids)
        except Exception:
            pass
    try:
        if not (msg.open_at and is_sealed(msg, None)):
            _bot_updates(db, chat, msg, sender)
    except Exception:
        pass
    try:
        from app import builtin_bots
        builtin_bots.dispatch(db, chat, msg, sender)
    except Exception as e:  # noqa: BLE001
        import logging
        logging.getLogger("connecto").warning("builtin bots: %s", e)
    return payload


def _quiet_call(msg: Message) -> bool:
    """История звонка: пуш нужен только о пропущенном."""
    if msg.kind != "call":
        return False
    info = (_extra(msg) or {}).get("call") or {}
    return info.get("status") not in ("missed", "busy")


async def purge_expired(db: Session) -> int:
    """Удалить исчезнувшие сообщения и разослать msg_deleted."""
    rows = (db.query(Message).filter(Message.expires_at.isnot(None),
                                     Message.expires_at <= _now()).limit(500).all())
    if not rows:
        return 0
    by_chat: dict = defaultdict(list)
    for m in rows:
        by_chat[m.chat_id].append(m.id)
    ids_all = [m.id for m in rows]
    db.query(MessageReaction).filter(MessageReaction.message_id.in_(ids_all)).delete(
        synchronize_session=False)
    db.query(Message).filter(Message.id.in_(ids_all)).delete(synchronize_session=False)
    db.commit()
    for chat_id, mids in by_chat.items():
        members = member_ids(db, chat_id)
        for mid in mids:
            await manager.send_to_users(members, {"type": "msg_deleted", "chat_id": chat_id,
                                                  "id": mid, "expired": True})
    return len(rows)


def deliver_sync(db: Session, chat: Chat, msg: Message, sender: User | None) -> None:
    """Вызов deliver из синхронного эндпоинта (он крутится в пуле потоков)."""
    try:
        import anyio.from_thread
        anyio.from_thread.run(deliver, db, chat, msg, sender)
    except Exception:
        pass


def send_ws_sync(user_ids: list[str], payload: dict) -> None:
    try:
        import anyio.from_thread
        anyio.from_thread.run(manager.send_to_users, user_ids, payload)
    except Exception:
        pass


async def _push_offline(db: Session, chat: Chat, msg: Message, sender: User | None,
                        ids: list[str]) -> None:
    members = {m.user_id: m for m in
               db.query(ChatMember).filter(ChatMember.chat_id == chat.id)}
    targets = []
    support_ids = {uid for uid, m in members.items() if m.role == "support"} if chat.is_system else set()
    for uid in ids:
        if sender is not None and uid == sender.id:
            continue
        if uid in support_ids and sender is not None and sender.is_bot:
            continue   # ответ поддержки (или уведомление) — другим админам пуш не нужен
        m = members.get(uid)
        if m is None or is_muted(m):
            continue
        targets.append(uid)
    if not targets:
        return
    users = {u.id: u for u in db.query(User).filter(User.id.in_(targets))}
    body_full = preview_text(msg, None) or ""
    s_name = (sender.display_name or sender.username) if sender else ""
    groups: dict = defaultdict(list)  # (title, body) -> tokens
    for uid in targets:
        u = users.get(uid)
        if u is None or u.is_bot:
            continue
        pref = get_notify(u)
        key = {"direct": "private", "group": "groups", "channel": "channels"}.get(chat.type, "private")
        if not pref.get(key, True):
            continue
        if uid in support_ids:
            title, body = f"🛟 Поддержка · {s_name}", body_full
        elif chat.type == "direct":
            title, body = s_name, body_full
        elif chat.type == "group":
            title, body = (chat.title or "Группа"), f"{s_name}: {body_full}"
        else:
            title, body = (chat.title or "Канал"), body_full
        if not pref.get("preview", True):
            body = "Новое сообщение"
        for t in db.query(PushToken).filter(PushToken.user_id == uid):
            groups[(title, body)].append(t.token)
    image = (chat.avatar_url if chat.type != "direct" else (sender.avatar_url if sender else None))
    for (title, body), tokens in groups.items():
        data = {
            "type": "message",
            "chat_id": chat.id,
            "message_id": msg.id,
            "title": title,
            "body": body,
            "avatar_url": image or "",
        }
        await run_in_threadpool(send_push, tokens, title, body, image, "messages", None, data)


# ── боты ──

def _bot_updates(db: Session, chat: Chat, msg: Message, sender: User | None) -> None:
    if msg.kind in ("service", "call"):
        return
    bots = (db.query(User).join(ChatMember, ChatMember.user_id == User.id)
            .filter(ChatMember.chat_id == chat.id, User.is_bot == True)  # noqa: E712
            .all())
    if not bots:
        return
    roles = {m.user_id: m.role for m in db.query(ChatMember).filter(ChatMember.chat_id == chat.id)}
    for bot in bots:
        if bot.bot_owner_id is None:   # системный бот Connecto — не отдаём обновления
            continue
        if sender is not None and sender.id == bot.id:
            continue
        if chat.type != "direct" and roles.get(bot.id) not in ("owner", "admin"):
            # в группах бот без админки видит только команды и упоминания
            t = (msg.text or "")
            mention = f"@{bot.handle or bot.username}".lower()
            if not (t.startswith("/") or mention in t.lower()):
                continue
        upd = BotUpdate(bot_id=bot.id, payload="{}")
        db.add(upd)
        db.flush()
        data = {"update_id": upd.id, "message": bot_message_obj(chat, msg, sender)}
        upd.payload = json.dumps(data, ensure_ascii=False)
        db.commit()
        if bot.bot_webhook:
            _post_webhook(bot.bot_webhook, data, upd.id)


def bot_message_obj(chat: Chat, msg: Message, sender: User | None) -> dict:
    ctype = {"direct": "private", "group": "group", "channel": "channel"}.get(chat.type, chat.type)
    obj = {
        "message_id": msg.id,
        "date": int(msg.created_at.timestamp()) if msg.created_at else int(time.time()),
        "chat": {"id": chat.id, "type": ctype, "title": chat.title},
        "text": msg.text if msg.kind == "text" else None,
        "kind": msg.kind,
    }
    if msg.media_url:
        obj["media_url"] = msg.media_url
    if msg.reply_to_id:
        obj["reply_to_message_id"] = msg.reply_to_id
    if sender is not None:
        obj["from"] = {"id": sender.id, "is_bot": bool(sender.is_bot),
                       "first_name": sender.display_name or sender.username,
                       "username": sender.handle or sender.username}
    return obj


def _post_webhook(url: str, data: dict, update_id: int) -> None:
    def run():
        try:
            import urllib.request
            req = urllib.request.Request(
                url, data=json.dumps(data, ensure_ascii=False).encode("utf-8"),
                headers={"Content-Type": "application/json"}, method="POST")
            with urllib.request.urlopen(req, timeout=8) as r:
                ok = 200 <= r.status < 300
        except Exception:
            ok = False
        if ok:
            from app.database import SessionLocal
            s = SessionLocal()
            try:
                s.query(BotUpdate).filter(BotUpdate.id == update_id).delete()
                s.commit()
            finally:
                s.close()
    threading.Thread(target=run, daemon=True).start()


# ── сервисные сообщения ──

def service_message(db: Session, chat: Chat, actor: User, text: str) -> Message:
    msg = Message(chat_id=chat.id, sender_id=actor.id, kind="service", text=text)
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return msg
