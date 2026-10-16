import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.deps import get_current_user, get_db
from app.models.user import User
from app.models.chat import (Block, PushToken, Message, ChatMember, ChatRead, Chat,
                             KnownDevice, LoginEvent, UserSession, MessageReaction,
                             BotUpdate, ChatBan)
from app.schemas.user import HandleUpdate, ProfileUpdate
from app.core.security import hash_password, verify_password
from app.privacy import (is_blocked, set_privacy, get_notify, NOTIFY_DEFAULTS,
                         public_user, is_premium)
from app.users_out import me_dict
from app.realtime import manager

router = APIRouter(tags=["users"])

REPORTS_FILE = "reports.jsonl"


class PushTokenIn(BaseModel):
    token: str


@router.post("/push/token", status_code=204)
def save_push_token(data: PushTokenIn, db: Session = Depends(get_db),
                    current_user: User = Depends(get_current_user)):
    if not data.token:
        return
    row = db.query(PushToken).filter(PushToken.token == data.token).first()
    if row is None:
        db.add(PushToken(token=data.token, user_id=current_user.id))
    else:
        row.user_id = current_user.id
    db.commit()


@router.delete("/push/token", status_code=204)
def drop_push_token(data: PushTokenIn, db: Session = Depends(get_db),
                    current_user: User = Depends(get_current_user)):
    db.query(PushToken).filter(PushToken.token == data.token,
                               PushToken.user_id == current_user.id).delete()
    db.commit()


# ── блокировки ──

@router.post("/users/{user_id}/block", status_code=204)
def block_user(user_id: str, db: Session = Depends(get_db),
               current_user: User = Depends(get_current_user)):
    if user_id == current_user.id:
        return
    if not is_blocked(db, current_user.id, user_id):
        db.add(Block(blocker_id=current_user.id, blocked_id=user_id))
        db.commit()


@router.delete("/users/{user_id}/block", status_code=204)
def unblock_user(user_id: str, db: Session = Depends(get_db),
                 current_user: User = Depends(get_current_user)):
    db.query(Block).filter(Block.blocker_id == current_user.id,
                           Block.blocked_id == user_id).delete()
    db.commit()


@router.get("/users/blocks")
def my_blocks(db: Session = Depends(get_db),
              current_user: User = Depends(get_current_user)):
    ids = [b.blocked_id for b in db.query(Block).filter(Block.blocker_id == current_user.id)]
    if not ids:
        return []
    return [public_user(db, u, current_user.id)
            for u in db.query(User).filter(User.id.in_(ids)).all()]


@router.get("/users/{user_id}/block")
def block_status(user_id: str, db: Session = Depends(get_db),
                 current_user: User = Depends(get_current_user)):
    return {"blocked": is_blocked(db, current_user.id, user_id)}


# ── жалобы ──

class ReportIn(BaseModel):
    target_id: str | None = None
    chat_id: str | None = None
    reason: str | None = None


@router.post("/report", status_code=204)
def report(data: ReportIn, current_user: User = Depends(get_current_user)):
    line = {
        "at": datetime.now(timezone.utc).isoformat(),
        "from": current_user.username,
        "from_id": current_user.id,
        "target_id": data.target_id,
        "chat_id": data.chat_id,
        "reason": (data.reason or "")[:500],
    }
    try:
        with open(REPORTS_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(line, ensure_ascii=False) + "\n")
    except Exception:
        pass


# ── я ──

@router.get("/me")
def me(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return me_dict(db, current_user)


@router.patch("/me")
def update_me(data: ProfileUpdate, db: Session = Depends(get_db),
              current_user: User = Depends(get_current_user)):
    if data.display_name is not None:
        current_user.display_name = data.display_name.strip() or current_user.display_name
    if data.last_name is not None:
        current_user.last_name = data.last_name.strip()
    if data.bio is not None:
        limit = 300 if is_premium(current_user) else 140
        if data.bio != (current_user.bio or "") and len(data.bio) > limit:
            raise HTTPException(status_code=400,
                                detail=f"Описание — до {limit} символов"
                                       + ("" if limit == 300 else " (с Premium — до 300)"))
        current_user.bio = data.bio
    if data.phone is not None:
        current_user.phone = data.phone.strip()
    if data.birthday is not None:
        current_user.birthday = data.birthday
    if data.avatar_url is not None:
        current_user.avatar_url = data.avatar_url or None
    if data.lastseen_privacy is not None:
        current_user.lastseen_privacy = data.lastseen_privacy
    if data.cover_url is not None:
        current_user.cover_item = None   # своя обложка снимает обложку из магазина
        if not data.cover_url:
            current_user.cover_url = None
            current_user.cover_kind = None
        else:
            kind = data.cover_kind or "image"
            if kind == "video" and not is_premium(current_user):
                raise HTTPException(status_code=403,
                                    detail="Видео-обложка доступна с Connecto Premium")
            current_user.cover_url = data.cover_url
            current_user.cover_kind = kind
    if data.emoji_status is not None:
        e = data.emoji_status.strip()
        if e and not is_premium(current_user):
            raise HTTPException(status_code=403, detail="Эмодзи-статус доступен с Connecto Premium")
        current_user.emoji_status = e or None
    if data.avatar_ring is not None:
        current_user.avatar_ring = data.avatar_ring
    db.commit()
    db.refresh(current_user)
    return me_dict(db, current_user)


class PrivacyIn(BaseModel):
    values: dict[str, str] = {}
    read_receipts: bool | None = None


@router.put("/me/privacy")
def update_privacy(data: PrivacyIn, db: Session = Depends(get_db),
                   current_user: User = Depends(get_current_user)):
    set_privacy(current_user, data.values)
    if data.read_receipts is not None:
        current_user.read_receipts = data.read_receipts
    db.commit()
    return me_dict(db, current_user)


@router.put("/me/notify")
def update_notify(data: dict[str, bool], db: Session = Depends(get_db),
                  current_user: User = Depends(get_current_user)):
    cur = get_notify(current_user)
    for k, v in data.items():
        if k in NOTIFY_DEFAULTS:
            cur[k] = bool(v)
    current_user.notify = json.dumps(cur)
    db.commit()
    return cur


class PasswordChange(BaseModel):
    old_password: str
    new_password: str = Field(min_length=8, max_length=128)


@router.post("/me/password")
def change_password(data: PasswordChange, db: Session = Depends(get_db),
                    current_user: User = Depends(get_current_user)):
    if not verify_password(data.old_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Текущий пароль неверный")
    current_user.password_hash = hash_password(data.new_password)
    # на других устройствах — выйти
    sid = getattr(current_user, "_sid", None)
    q = db.query(UserSession).filter(UserSession.user_id == current_user.id)
    if sid:
        q = q.filter(UserSession.id != sid)
    q.delete()
    db.commit()
    return {"ok": True}


# ── смена почты: пароль → код на новую почту → подтверждение ──

class EmailStart(BaseModel):
    new_email: EmailStr
    password: str


class EmailConfirm(BaseModel):
    new_email: EmailStr
    code: str


def _check_new_email(db: Session, user: User, email: str) -> None:
    if email == (user.email or "").lower():
        raise HTTPException(status_code=400, detail="Это твоя текущая почта")
    if db.query(User).filter(User.email == email, User.id != user.id).first():
        raise HTTPException(status_code=409, detail="Эта почта уже привязана к другому аккаунту")


def _apply_email(db: Session, user: User, email: str) -> dict:
    from app import email_service, sysbot
    from app.routers.auth import _mask_email
    old = user.email
    user.email = email
    db.commit()
    db.refresh(user)
    try:
        email_service.send_email_changed_notice(old, _mask_email(email))
    except Exception:
        pass
    try:
        sysbot.post(db, user, f"✉️ Почта аккаунта изменена на {_mask_email(email)}.\n\n"
                              "Если это были не вы — смените пароль и завершите чужие сеансы.")
    except Exception:
        pass
    return me_dict(db, user)


@router.post("/me/email")
def email_change_start(data: EmailStart, db: Session = Depends(get_db),
                       current_user: User = Depends(get_current_user)):
    from app import email_service, verify
    from app.routers.auth import _mask_email
    key = "pw:" + current_user.id
    if verify.too_many(key):
        raise HTTPException(status_code=429, detail="Слишком много попыток. Подожди 15 минут.")
    if not verify_password(data.password, current_user.password_hash):
        verify.fail(key)
        raise HTTPException(status_code=400, detail="Неверный пароль")
    verify.reset(key)
    email = data.new_email.strip().lower()
    _check_new_email(db, current_user, email)
    if not email_service.enabled():
        from app.config import is_admin_email
        if is_admin_email(email):
            raise HTTPException(status_code=403, detail="Эту почту можно привязать только с подтверждением")
        # отправка писем не настроена — меняем сразу
        return {"changed": True, "user": _apply_email(db, current_user, email)}
    send_key = "mailsend:" + current_user.id
    if verify.too_many(send_key):
        raise HTTPException(status_code=429, detail="Слишком много писем. Подожди 15 минут.")
    verify.fail(send_key)
    code = verify.gen_and_store(f"chmail:{current_user.id}:{email}")
    if not email_service.send_email_change_code(email, code):
        raise HTTPException(status_code=503, detail="Не удалось отправить письмо на эту почту")
    return {"sent": True, "email_masked": _mask_email(email)}


@router.post("/me/email/confirm")
def email_change_confirm(data: EmailConfirm, db: Session = Depends(get_db),
                         current_user: User = Depends(get_current_user)):
    from app import verify
    email = data.new_email.strip().lower()
    if not verify.check(f"chmail:{current_user.id}:{email}", data.code):
        raise HTTPException(status_code=400, detail="Неверный или истёкший код")
    _check_new_email(db, current_user, email)
    return _apply_email(db, current_user, email)


class CloudPasswordIn(BaseModel):
    current: str | None = None
    new: str | None = Field(default=None, min_length=4, max_length=128)
    hint: str | None = Field(default=None, max_length=64)


@router.put("/me/cloud_password")
def set_cloud_password(data: CloudPasswordIn, db: Session = Depends(get_db),
                       current_user: User = Depends(get_current_user)):
    """Включить / сменить / выключить облачный пароль (new=None → выключить)."""
    if current_user.cloud_password_hash:
        if not data.current or not verify_password(data.current, current_user.cloud_password_hash):
            raise HTTPException(status_code=400, detail="Текущий облачный пароль неверный")
    if data.new:
        if data.hint and data.hint.strip() == data.new:
            raise HTTPException(status_code=400, detail="Подсказка не должна совпадать с паролем")
        current_user.cloud_password_hash = hash_password(data.new)
        current_user.cloud_password_hint = (data.hint or "").strip() or None
    else:
        current_user.cloud_password_hash = None
        current_user.cloud_password_hint = None
    db.commit()
    return me_dict(db, current_user)


# ── сеансы ──

@router.get("/sessions")
def list_sessions(db: Session = Depends(get_db),
                  current_user: User = Depends(get_current_user)):
    sid = getattr(current_user, "_sid", None)
    rows = (db.query(UserSession).filter(UserSession.user_id == current_user.id)
            .order_by(UserSession.last_active.desc()).all())
    return [{
        "id": s.id,
        "platform": s.platform,
        "city": s.city,
        "ip": s.ip,
        "created_at": s.created_at.isoformat() if s.created_at else None,
        "last_active": s.last_active.isoformat() if s.last_active else None,
        "current": s.id == sid,
    } for s in rows]


async def _kick_sessions(user_id: str) -> None:
    await manager.send_to_users([user_id], {"type": "sessions_changed"})


@router.delete("/sessions/{session_id}", status_code=204)
async def terminate_session(session_id: str, db: Session = Depends(get_db),
                            current_user: User = Depends(get_current_user)):
    s = db.query(UserSession).filter(UserSession.id == session_id,
                                     UserSession.user_id == current_user.id).first()
    if s is None:
        raise HTTPException(status_code=404, detail="Сеанс не найден")
    # устройство перестаёт быть доверенным — повторный вход снова с кодом
    if s.device_id:
        db.query(KnownDevice).filter(KnownDevice.user_id == current_user.id,
                                     KnownDevice.device_id == s.device_id).delete()
    db.delete(s)
    db.commit()
    await _kick_sessions(current_user.id)


@router.delete("/sessions", status_code=204)
async def terminate_other_sessions(db: Session = Depends(get_db),
                                   current_user: User = Depends(get_current_user)):
    sid = getattr(current_user, "_sid", None)
    q = db.query(UserSession).filter(UserSession.user_id == current_user.id)
    keep_device = None
    if sid:
        cur = db.query(UserSession).filter(UserSession.id == sid).first()
        keep_device = cur.device_id if cur else None
        q = q.filter(UserSession.id != sid)
    q.delete()
    kq = db.query(KnownDevice).filter(KnownDevice.user_id == current_user.id)
    if keep_device:
        kq = kq.filter(KnownDevice.device_id != keep_device)
    kq.delete()
    db.commit()
    await _kick_sessions(current_user.id)


# ── удаление аккаунта ──

def delete_user_everywhere(db: Session, uid: str) -> None:
    for model, col in ((Message, Message.sender_id), (ChatMember, ChatMember.user_id),
                       (ChatRead, ChatRead.user_id), (PushToken, PushToken.user_id),
                       (KnownDevice, KnownDevice.user_id), (LoginEvent, LoginEvent.user_id),
                       (UserSession, UserSession.user_id),
                       (MessageReaction, MessageReaction.user_id),
                       (ChatBan, ChatBan.user_id), (BotUpdate, BotUpdate.bot_id)):
        db.query(model).filter(col == uid).delete(synchronize_session=False)
    db.query(Block).filter(or_(Block.blocker_id == uid, Block.blocked_id == uid)).delete(
        synchronize_session=False)
    from app.models.social import Story, StoryView, UserGift, CoinTx, Payment
    for model, col in ((Story, Story.user_id), (StoryView, StoryView.viewer_id),
                       (UserGift, UserGift.to_id), (CoinTx, CoinTx.user_id),
                       (Payment, Payment.user_id)):
        db.query(model).filter(col == uid).delete(synchronize_session=False)
    # чаты, где он был владельцем: передаём права или удаляем пустые
    for chat in db.query(Chat).filter(Chat.owner_id == uid).all():
        nxt = (db.query(ChatMember).filter(ChatMember.chat_id == chat.id)
               .order_by(ChatMember.role.asc(), ChatMember.joined_at.asc()).first())
        if nxt is None:
            db.query(Message).filter(Message.chat_id == chat.id).delete(synchronize_session=False)
            db.delete(chat)
        else:
            nxt.role = "owner"
            chat.owner_id = nxt.user_id
    user = db.query(User).filter(User.id == uid).first()
    if user is not None:
        db.delete(user)


@router.delete("/me", status_code=204)
def delete_me(db: Session = Depends(get_db),
              current_user: User = Depends(get_current_user)):
    """Удалить свой аккаунт со всеми данными (и своих ботов)."""
    for bot in db.query(User).filter(User.bot_owner_id == current_user.id).all():
        delete_user_everywhere(db, bot.id)
    delete_user_everywhere(db, current_user.id)
    db.commit()


# ── юзернейм и поиск ──

@router.post("/users/handle")
def set_handle(data: HandleUpdate, db: Session = Depends(get_db),
               current_user: User = Depends(get_current_user)):
    h = data.handle.strip().lstrip("@")
    exists = (db.query(User).filter(User.handle == h, User.id != current_user.id).first()
              or db.query(Chat).filter(Chat.handle == h).first())
    if exists:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="Этот юзернейм уже занят")
    current_user.handle = h
    db.commit()
    db.refresh(current_user)
    return me_dict(db, current_user)


@router.get("/users/search")
def search_users(q: str, db: Session = Depends(get_db),
                 current_user: User = Depends(get_current_user)):
    q = q.strip().lstrip("@")
    if not q:
        return []
    like = f"%{q}%"
    rows = (db.query(User)
            .filter(User.handle.isnot(None))
            .filter(or_(User.handle.ilike(like), User.display_name.ilike(like)))
            .filter(User.id != current_user.id)
            .filter(User.banned == False)  # noqa: E712
            .limit(30).all())
    # кто меня заблокировал — не показываем
    return [public_user(db, u, current_user.id) for u in rows
            if not is_blocked(db, u.id, current_user.id)]


@router.get("/users/{user_id}")
def user_profile(user_id: str, db: Session = Depends(get_db),
                 current_user: User = Depends(get_current_user)):
    u = db.query(User).filter(User.id == user_id).first()
    if u is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    out = public_user(db, u, current_user.id)
    from app.routers.chats import presence_of
    online, seen = presence_of(db, u, current_user.id)
    out["online"] = online
    out["last_seen"] = seen.isoformat() if seen else None
    out["blocked_by_me"] = is_blocked(db, current_user.id, u.id)
    # личный чат с ним (если уже есть) — для кнопки «Звук» и вложений в профиле
    out["chat_id"] = None
    if u.id != current_user.id:
        from app.models.chat import Chat, ChatMember
        mine = db.query(ChatMember.chat_id).filter(ChatMember.user_id == current_user.id)
        row = (db.query(Chat.id).join(ChatMember, ChatMember.chat_id == Chat.id)
               .filter(Chat.type == "direct", Chat.is_system == False,  # noqa: E712
                       ChatMember.user_id == u.id, Chat.id.in_(mine)).first())
        out["chat_id"] = row[0] if row else None
    try:
        from app.routers.economy import profile_counts
        out.update(profile_counts(db, u, current_user.id))
    except Exception:
        out.update({"gifts_count": 0, "posts_count": 0, "has_stories": False})
    if u.is_bot and u.bot_commands:
        try:
            out["commands"] = json.loads(u.bot_commands)
        except Exception:
            out["commands"] = []
    return out
