"""Админ-панель: пользователи, бан, удаление, Premium, промокоды, жалобы,
статистика и поддержка (переписка от имени бота Connecto).
Доступ только у аккаунтов, чей email в ADMIN_EMAILS (config.py)."""
import json
import os
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import or_, func
from sqlalchemy.orm import Session

from app.deps import get_db, require_admin
from app.config import is_admin_email
from app.models.user import User
from app.models.chat import (Chat, ChatMember, Message, PromoCode, UserSession)
from app.models.social import UserGift, Story, Payment, CoinTx
from app.privacy import is_premium, as_utc
from app.realtime import manager
from app.messaging import message_dict, deliver
from app import sysbot

router = APIRouter(prefix="/admin", tags=["admin"])


def _as_dict(u: User) -> dict:
    pu = as_utc(u.premium_until)
    return {
        "id": u.id,
        "username": u.username,
        "handle": u.handle,
        "email": u.email if not u.is_bot else None,
        "display_name": u.display_name,
        "avatar_url": u.avatar_url,
        "banned": bool(getattr(u, "banned", False)),
        "is_admin": is_admin_email(u.email),
        "is_bot": bool(u.is_bot),
        "is_premium": is_premium(u),
        "premium_until": pu.isoformat() if pu else None,
        "online": manager.is_online(u.id),
        "created_at": u.created_at.isoformat() if u.created_at else None,
        "last_seen": u.last_seen.isoformat() if u.last_seen else None,
        "is_verified": bool(u.is_verified),
        "emoji_status": u.emoji_status,
        "coins": int(u.coins or 0),
    }


def _daily(dates: list, days: int = 14) -> list:
    """Количество по дням за последние N дней (старые → новые)."""
    today = datetime.now(timezone.utc).date()
    counts = {today - timedelta(days=i): 0 for i in range(days)}
    for d in dates:
        d = as_utc(d)
        if d is None:
            continue
        day = d.date()
        if day in counts:
            counts[day] += 1
    return [{"date": k.isoformat(), "count": counts[k]} for k in sorted(counts)]


@router.get("/stats")
def stats(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    since = datetime.now(timezone.utc) - timedelta(days=14)
    humans = db.query(User).filter(User.is_bot == False)  # noqa: E712
    return {
        "users": humans.count(),
        "bots": db.query(User).filter(User.is_bot == True, User.bot_owner_id.isnot(None)).count(),  # noqa: E712
        "online": len(manager.active),
        "premium": sum(1 for u in humans.all() if is_premium(u)),
        "banned": humans.filter(User.banned == True).count(),  # noqa: E712
        "direct": db.query(Chat).filter(Chat.type == "direct").count(),
        "groups": db.query(Chat).filter(Chat.type == "group").count(),
        "channels": db.query(Chat).filter(Chat.type == "channel").count(),
        "messages": db.query(Message).count(),
        "sessions": db.query(UserSession).count(),
        "daily_users": _daily([r[0] for r in db.query(User.created_at).filter(
            User.is_bot == False, User.created_at >= since).all()]),  # noqa: E712
        "daily_messages": _daily([r[0] for r in db.query(Message.created_at).filter(
            Message.created_at >= since).all()]),
        "coins_total": int(db.query(func.coalesce(func.sum(User.coins), 0)).scalar() or 0),
        "gifts": db.query(UserGift).count(),
        "commission_coins": int(db.query(func.coalesce(func.sum(CoinTx.amount), 0))
                                .filter(CoinTx.kind == "market_commission").scalar() or 0),
        "stories": db.query(Story).filter(Story.deleted_at.is_(None)).count(),
        "payments_rub": int(db.query(func.coalesce(func.sum(Payment.rub), 0))
                            .filter(Payment.status == "succeeded").scalar() or 0),
    }


@router.get("/users")
def list_users(q: str = "", db: Session = Depends(get_db),
               admin: User = Depends(require_admin)):
    query = db.query(User).filter(User.email != sysbot.SYSTEM_EMAIL)
    q = (q or "").strip().lstrip("@")
    if q:
        like = f"%{q}%"
        query = query.filter(or_(User.username.ilike(like), User.display_name.ilike(like),
                                 User.email.ilike(like), User.handle.ilike(like)))
    users = query.order_by(User.created_at.desc()).limit(500).all()
    return [_as_dict(u) for u in users]


def _target(db: Session, user_id: str) -> User:
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    return user


@router.post("/users/{user_id}/ban")
async def ban_user(user_id: str, db: Session = Depends(get_db),
                   admin: User = Depends(require_admin)):
    user = _target(db, user_id)
    if is_admin_email(user.email):
        raise HTTPException(status_code=400, detail="Нельзя забанить админа")
    user.banned = True
    db.query(UserSession).filter(UserSession.user_id == user.id).delete()
    db.commit()
    await manager.send_to_users([user.id], {"type": "sessions_changed"})
    return {"ok": True, "banned": True}


@router.post("/users/{user_id}/unban")
def unban_user(user_id: str, db: Session = Depends(get_db),
               admin: User = Depends(require_admin)):
    user = _target(db, user_id)
    user.banned = False
    db.commit()
    return {"ok": True, "banned": False}


@router.delete("/users/{user_id}", status_code=204)
async def delete_user(user_id: str, db: Session = Depends(get_db),
                      admin: User = Depends(require_admin)):
    user = _target(db, user_id)
    if is_admin_email(user.email) or user.email == sysbot.SYSTEM_EMAIL:
        raise HTTPException(status_code=400, detail="Нельзя удалить этот аккаунт")
    from app.routers.users import delete_user_everywhere
    for bot in db.query(User).filter(User.bot_owner_id == user.id).all():
        delete_user_everywhere(db, bot.id)
    delete_user_everywhere(db, user.id)
    db.commit()
    await manager.send_to_users([user_id], {"type": "sessions_changed"})


class PremiumIn(BaseModel):
    days: int = Field(ge=0, le=3650)   # 0 — снять


@router.post("/users/{user_id}/premium")
def set_premium(user_id: str, data: PremiumIn, db: Session = Depends(get_db),
                admin: User = Depends(require_admin)):
    from app.routers.premium import grant
    user = _target(db, user_id)
    if data.days == 0:
        user.premium_until = None
    else:
        grant(user, data.days)
    db.commit()
    from app.messaging import send_ws_sync
    send_ws_sync([user.id], {"type": "me_updated"})
    if data.days:
        try:
            sysbot.post(db, user, f"⭐ Вам подарен Connecto Premium на {data.days} дн.! "
                                  "Спасибо, что вы с нами.")
        except Exception:
            pass
    return _as_dict(user)


# ── промокоды ──

class PromoIn(BaseModel):
    days: int = Field(default=0, ge=0, le=3650)
    coins: int = Field(default=0, ge=0, le=1000000)
    uses: int = Field(default=1, ge=1, le=100000)
    code: str | None = Field(default=None, max_length=32)


@router.get("/promo")
def list_promo(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    rows = db.query(PromoCode).order_by(PromoCode.created_at.desc()).all()
    return [{"code": p.code, "days": p.days, "coins": int(p.coins or 0), "uses_left": p.uses_left,
             "created_at": p.created_at.isoformat() if p.created_at else None} for p in rows]


@router.post("/promo", status_code=201)
def create_promo(data: PromoIn, db: Session = Depends(get_db),
                 admin: User = Depends(require_admin)):
    code = (data.code or "").strip().upper() or ("CONNECTO-" + secrets.token_hex(3).upper())
    if db.query(PromoCode).filter(PromoCode.code == code).first():
        raise HTTPException(status_code=409, detail="Такой код уже есть")
    if not data.days and not data.coins:
        raise HTTPException(status_code=400, detail="Укажи дни Premium или коины")
    db.add(PromoCode(code=code, days=data.days, coins=data.coins, uses_left=data.uses))
    db.commit()
    return {"code": code, "days": data.days, "coins": data.coins, "uses_left": data.uses}


@router.delete("/promo/{code}", status_code=204)
def delete_promo(code: str, db: Session = Depends(get_db),
                 admin: User = Depends(require_admin)):
    db.query(PromoCode).filter(PromoCode.code == code.upper()).delete()
    db.commit()


# ── жалобы ──

@router.get("/reports")
def reports(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    from app.routers.users import REPORTS_FILE
    if not os.path.exists(REPORTS_FILE):
        return []
    with open(REPORTS_FILE, "r", encoding="utf-8") as f:
        lines = f.readlines()[-300:]
    out = []
    for line in reversed(lines):
        try:
            r = json.loads(line)
        except Exception:
            continue
        t = db.query(User).filter(User.id == r.get("target_id")).first() if r.get("target_id") else None
        c = db.query(Chat).filter(Chat.id == r.get("chat_id")).first() if r.get("chat_id") else None
        r["target_name"] = (t.display_name or t.username) if t else None
        r["chat_title"] = (c.title if c and c.type != "direct" else None)
        out.append(r)
    return out


# ── поддержка (переписка с пользователями от имени Connecto) ──

@router.get("/support")
def support_list(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    bot = sysbot.get_bot(db)
    out = []
    for chat in db.query(Chat).filter(Chat.is_system == True).all():  # noqa: E712
        user = sysbot.support_owner(db, chat)
        if user is None:
            continue
        last_user = (db.query(Message).filter(Message.chat_id == chat.id,
                                              Message.sender_id == user.id)
                     .order_by(Message.created_at.desc()).first())
        if last_user is None:
            continue   # человек ничего не писал — это просто уведомления
        last_bot = (db.query(Message).filter(Message.chat_id == chat.id,
                                             Message.sender_id == bot.id)
                    .order_by(Message.created_at.desc()).first())
        waiting = last_bot is None or as_utc(last_bot.created_at) < as_utc(last_user.created_at)
        out.append({"chat_id": chat.id, "user": _as_dict(user),
                    "last_text": last_user.text if last_user.kind == "text" else "Вложение",
                    "last_time": last_user.created_at.isoformat(),
                    "waiting": waiting})
    out.sort(key=lambda x: (not x["waiting"], x["last_time"]), reverse=False)
    out.sort(key=lambda x: x["waiting"], reverse=True)
    return out


@router.get("/support/{chat_id}")
def support_messages(chat_id: str, db: Session = Depends(get_db),
                     admin: User = Depends(require_admin)):
    chat = db.query(Chat).filter(Chat.id == chat_id, Chat.is_system == True).first()  # noqa: E712
    if chat is None:
        raise HTTPException(status_code=404, detail="Диалог не найден")
    msgs = (db.query(Message).filter(Message.chat_id == chat_id)
            .order_by(Message.created_at.desc()).limit(200).all())
    msgs.reverse()
    senders = {u.id: u for u in db.query(User).filter(User.id.in_({m.sender_id for m in msgs}))}
    return [message_dict(m, chat, senders.get(m.sender_id)) for m in msgs]


class SupportReply(BaseModel):
    text: str = Field(min_length=1, max_length=4000)


@router.post("/support/{chat_id}")
async def support_reply(chat_id: str, data: SupportReply, db: Session = Depends(get_db),
                        admin: User = Depends(require_admin)):
    chat = db.query(Chat).filter(Chat.id == chat_id, Chat.is_system == True).first()  # noqa: E712
    if chat is None:
        raise HTTPException(status_code=404, detail="Диалог не найден")
    bot = sysbot.get_bot(db)
    msg = Message(chat_id=chat.id, sender_id=bot.id, kind="text", text=data.text.strip(),
                  extra=sysbot.SUPPORT_TAG)
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return await deliver(db, chat, msg, bot)


class BroadcastIn(BaseModel):
    text: str = Field(min_length=1, max_length=4000)
    target: str = Field(default="all")  # all | premium | non_premium | restricted | specific
    user_ids: list[str] = Field(default_factory=list)


@router.post("/broadcast")
def broadcast(data: BroadcastIn, db: Session = Depends(get_db),
              admin: User = Depends(require_admin)):
    """Рассылка пользователям от имени Connecto:
    target: 'all' | 'premium' | 'non_premium' | 'restricted' | 'specific'
    """
    now = datetime.now(timezone.utc)
    target = (data.target or "all").lower().strip()

    query = db.query(User).filter(User.is_bot == False)
    if target == "premium":
        query = query.filter(User.banned == False, User.premium_until != None, User.premium_until > now)
    elif target == "non_premium":
        query = query.filter(User.banned == False, or_(User.premium_until == None, User.premium_until <= now))
    elif target == "restricted":
        query = query.filter(User.banned == True)
    elif target == "specific":
        raw_ids = [x.strip().lstrip("@") for x in (data.user_ids or []) if x.strip()]
        if not raw_ids:
            return {"sent": 0, "target": target}
        query = query.filter(
            or_(
                User.id.in_(raw_ids),
                User.username.in_(raw_ids),
                User.handle.in_(raw_ids),
            )
        )
    else:
        query = query.filter(User.banned == False)

    targets = query.all()
    n = 0
    for u in targets:
        try:
            sysbot.post(db, u, data.text.strip())
            n += 1
        except Exception:
            pass
    return {"sent": n, "target": target}


# ── карточка пользователя и действия ──

@router.get("/users/{user_id}")
def user_detail(user_id: str, db: Session = Depends(get_db),
                admin: User = Depends(require_admin)):
    u = _target(db, user_id)
    out = _as_dict(u)
    out.update({
        "chats": db.query(ChatMember).filter(ChatMember.user_id == u.id).count(),
        "messages": db.query(Message).filter(Message.sender_id == u.id).count(),
        "bots": db.query(User).filter(User.bot_owner_id == u.id).count(),
        "sessions": [{
            "platform": s.platform, "city": s.city, "ip": s.ip,
            "last_active": s.last_active.isoformat() if s.last_active else None,
        } for s in db.query(UserSession).filter(UserSession.user_id == u.id)
            .order_by(UserSession.last_active.desc()).all()],
        "bio": u.bio,
    })
    return out


class FlagIn(BaseModel):
    value: bool


@router.post("/users/{user_id}/verify")
def verify_user(user_id: str, data: FlagIn, db: Session = Depends(get_db),
                admin: User = Depends(require_admin)):
    u = _target(db, user_id)
    u.is_verified = data.value
    db.commit()
    from app.messaging import send_ws_sync
    send_ws_sync([u.id], {"type": "me_updated"})
    return _as_dict(u)


@router.post("/users/{user_id}/logout")
def logout_user(user_id: str, db: Session = Depends(get_db),
                admin: User = Depends(require_admin)):
    u = _target(db, user_id)
    n = db.query(UserSession).filter(UserSession.user_id == u.id).delete()
    db.commit()
    from app.messaging import send_ws_sync
    send_ws_sync([u.id], {"type": "sessions_changed"})
    return {"ok": True, "sessions": n}


class TextIn(BaseModel):
    text: str = Field(min_length=1, max_length=4000)


@router.post("/users/{user_id}/message")
def message_user(user_id: str, data: TextIn, db: Session = Depends(get_db),
                 admin: User = Depends(require_admin)):
    u = _target(db, user_id)
    if u.is_bot:
        raise HTTPException(status_code=400, detail="Боту написать нельзя")
    sysbot.post(db, u, data.text.strip())
    return {"ok": True}


class CoinsIn(BaseModel):
    amount: int = Field(ge=-1000000, le=1000000)
    note: str | None = Field(default=None, max_length=100)


@router.post("/users/{user_id}/coins")
def give_coins(user_id: str, data: CoinsIn, db: Session = Depends(get_db),
               admin: User = Depends(require_admin)):
    from app.routers.economy import add_coins
    user = _target(db, user_id)
    if data.amount == 0:
        return _as_dict(user)
    if data.amount < 0 and int(user.coins or 0) + data.amount < 0:
        data.amount = -int(user.coins or 0)
    add_coins(db, user, data.amount, "admin",
              data.note or ("Начисление от Connecto" if data.amount > 0 else "Списание"))
    db.commit()
    from app.messaging import send_ws_sync
    send_ws_sync([user.id], {"type": "me_updated"})
    if data.amount > 0:
        try:
            sysbot.post(db, user, f"🪙 Вам начислено {data.amount} коинов!"
                                  + (f"\n{data.note}" if data.note else ""))
        except Exception:
            pass
    return _as_dict(user)


@router.get("/premium")
def premium_users(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    rows = db.query(User).filter(User.premium_until.isnot(None)).all()
    out = [_as_dict(u) for u in rows if is_premium(u)]
    out.sort(key=lambda x: x["premium_until"] or "")
    return out


# ── группы и каналы ──

def _chat_dict(db: Session, c: Chat) -> dict:
    owner = db.query(User).filter(User.id == c.owner_id).first() if c.owner_id else None
    return {
        "id": c.id, "type": c.type, "title": c.title, "handle": c.handle,
        "avatar_url": c.avatar_url, "description": c.description,
        "is_verified": bool(c.is_verified),
        "member_count": db.query(ChatMember).filter(ChatMember.chat_id == c.id).count(),
        "messages": db.query(Message).filter(Message.chat_id == c.id).count(),
        "owner_name": (owner.display_name or owner.username) if owner else None,
        "owner_id": c.owner_id,
        "created_at": c.created_at.isoformat() if c.created_at else None,
    }


@router.get("/chats")
def list_chats_admin(q: str = "", db: Session = Depends(get_db),
                     admin: User = Depends(require_admin)):
    query = db.query(Chat).filter(Chat.type.in_(["group", "channel"]))
    q = (q or "").strip().lstrip("@")
    if q:
        like = f"%{q}%"
        query = query.filter(or_(Chat.title.ilike(like), Chat.handle.ilike(like)))
    rows = query.order_by(Chat.created_at.desc()).limit(300).all()
    return [_chat_dict(db, c) for c in rows]


@router.post("/chats/{chat_id}/verify")
def verify_chat(chat_id: str, data: FlagIn, db: Session = Depends(get_db),
                admin: User = Depends(require_admin)):
    c = db.query(Chat).filter(Chat.id == chat_id).first()
    if c is None:
        raise HTTPException(status_code=404, detail="Чат не найден")
    c.is_verified = data.value
    db.commit()
    from app.messaging import send_ws_sync, member_ids
    send_ws_sync(member_ids(db, c.id), {"type": "chat_updated", "chat_id": c.id})
    return _chat_dict(db, c)


@router.delete("/chats/{chat_id}", status_code=204)
def delete_chat_admin(chat_id: str, db: Session = Depends(get_db),
                      admin: User = Depends(require_admin)):
    c = db.query(Chat).filter(Chat.id == chat_id).first()
    if c is None:
        return
    from app.messaging import send_ws_sync, member_ids
    from app.routers.chats import _delete_chat_rows
    members = member_ids(db, c.id)
    _delete_chat_rows(db, c)
    send_ws_sync(members, {"type": "chat_deleted", "chat_id": chat_id})



# ── экономика: подарки, коины ──

@router.get("/economy")
def economy(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    from app.routers.economy import all_gifts
    from app.models.social import CoinTx
    rows = db.query(UserGift).all()
    by_gift: dict = {}
    for r in rows:
        d = by_gift.setdefault(r.gift_id, {"sold": 0, "converted": 0, "upgraded": 0})
        d["sold"] += 1
        d["converted"] += 1 if r.converted else 0
        d["upgraded"] += 1 if r.upgraded else 0
    gifts = []
    for g, status in all_gifts(db):
        st = by_gift.get(g["id"], {"sold": 0, "converted": 0, "upgraded": 0})
        gifts.append({**g, **st, "status": status, "revenue": st["sold"] * g["price"]})
    top = (db.query(User).filter(User.is_bot == False)  # noqa: E712
           .order_by(User.coins.desc()).limit(20).all())
    txs = db.query(CoinTx).order_by(CoinTx.created_at.desc()).limit(60).all()
    names = {u.id: (u.display_name or u.username) for u in db.query(User).filter(
        User.id.in_({t.user_id for t in txs})).all()}
    spent = int(db.query(func.coalesce(func.sum(CoinTx.amount), 0))
                .filter(CoinTx.amount < 0).scalar() or 0)
    earned = int(db.query(func.coalesce(func.sum(CoinTx.amount), 0))
                 .filter(CoinTx.amount > 0).scalar() or 0)
    return {
        "gifts": gifts,
        "gifts_total": len(rows),
        "coins_spent": -spent,
        "coins_issued": earned,
        "top": [{"id": u.id, "display_name": u.display_name or u.username,
                 "avatar_url": u.avatar_url, "coins": int(u.coins or 0)} for u in top
                if (u.coins or 0) > 0],
        "transactions": [{"user_id": t.user_id, "name": names.get(t.user_id, "?"),
                          "amount": t.amount, "kind": t.kind, "title": t.title,
                          "created_at": as_utc(t.created_at).isoformat() if t.created_at else None}
                         for t in txs],
    }


@router.get("/users/{user_id}/coins")
def user_coin_history(user_id: str, db: Session = Depends(get_db),
                      admin: User = Depends(require_admin)):
    from app.models.social import CoinTx
    _target(db, user_id)
    rows = (db.query(CoinTx).filter(CoinTx.user_id == user_id)
            .order_by(CoinTx.created_at.desc()).limit(200).all())
    return [{"amount": r.amount, "kind": r.kind, "title": r.title,
             "created_at": as_utc(r.created_at).isoformat() if r.created_at else None}
            for r in rows]


class AdminGiftIn(BaseModel):
    gift_id: str
    text: str = Field(default="", max_length=200)


@router.post("/users/{user_id}/gift")
async def admin_gift(user_id: str, data: AdminGiftIn, db: Session = Depends(get_db),
                     admin: User = Depends(require_admin)):
    """Подарок от Connecto (бесплатно, приходит от бота)."""
    from app.routers.economy import get_gift, create_gift, gift_dict
    g = get_gift(db, data.gift_id)
    if g is None:
        raise HTTPException(status_code=404, detail="Подарок не найден")
    user = _target(db, user_id)
    if user.is_bot:
        raise HTTPException(status_code=400, detail="Ботам подарки не дарят")
    ug = await create_gift(db, g, user, None, data.text or "Подарок от команды Connecto 💜", False)
    return gift_dict(db, ug, admin.id)


# ── истории: модерация ──

@router.get("/stories")
def admin_stories(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    rows = (db.query(Story).filter(Story.deleted_at.is_(None))
            .order_by(Story.created_at.desc()).limit(120).all())
    users = {u.id: u for u in db.query(User).filter(User.id.in_({r.user_id for r in rows})).all()}
    now = datetime.now(timezone.utc)
    out = []
    for r in rows:
        u = users.get(r.user_id)
        out.append({"id": r.id, "media_url": r.media_url, "kind": r.kind, "caption": r.caption,
                    "pinned": bool(r.pinned), "active": as_utc(r.expires_at) > now,
                    "user": {"id": r.user_id,
                             "display_name": (u.display_name or u.username) if u else "?",
                             "avatar_url": u.avatar_url if u else None},
                    "created_at": as_utc(r.created_at).isoformat() if r.created_at else None})
    return out


@router.delete("/stories/{story_id}", status_code=204)
async def admin_delete_story(story_id: str, db: Session = Depends(get_db),
                             admin: User = Depends(require_admin)):
    s = db.query(Story).filter(Story.id == story_id).first()
    if s is None:
        raise HTTPException(status_code=404, detail="История не найдена")
    s.deleted_at = datetime.now(timezone.utc)
    db.commit()
    from app.routers.stories import contact_ids
    await manager.send_to_users([s.user_id] + contact_ids(db, s.user_id),
                                {"type": "story_deleted", "story_id": s.id, "user_id": s.user_id})



# ── магазин подарков: добавить / изменить / снять с продажи ──

class GiftDefIn(BaseModel):
    id: str | None = Field(default=None, max_length=32)   # пусто — придумаем сами
    title: str = Field(min_length=1, max_length=64)
    emoji: str = Field(default="🎁", max_length=16)
    image_url: str | None = Field(default=None, max_length=512)
    price: int = Field(ge=1, le=1_000_000)
    rarity: str = "common"
    supply: int | None = Field(default=None, ge=1, le=10_000_000)
    colors: list[str] | None = None
    sale_from: datetime | None = None
    sale_until: datetime | None = None
    active: bool = True
    sort: int | None = None
    bg: str | None = Field(default=None, max_length=24)
    fx: str | None = Field(default=None, max_length=24)
    anim: str | None = Field(default=None, max_length=16)
    symbol: str | None = Field(default=None, max_length=16)


def _gift_admin_dict(db: Session, row) -> dict:
    from app.routers.economy import def_dict, gift_status, CONVERT_RATE
    d = def_dict(row)
    sold = db.query(UserGift).filter(UserGift.gift_id == row.id).count()
    d.update({
        "active": bool(row.active),
        "sort": row.sort,
        "sold": sold,
        "left": max(0, row.supply - sold) if row.supply else None,
        "revenue": sold * int(row.price),
        "convert_value": int(row.price * CONVERT_RATE),
        "status": gift_status({"active": bool(row.active), "sale_from": as_utc(row.sale_from),
                               "sale_until": as_utc(row.sale_until)}),
    })
    return d


def _clean_colors(colors: list[str] | None) -> str | None:
    import re
    if not colors:
        return None
    ok = [c.upper() for c in colors if isinstance(c, str) and re.fullmatch(r"#[0-9A-Fa-f]{6}", c)]
    return ",".join(ok[:3]) or None


def _check_gift(data: GiftDefIn) -> None:
    from app.routers.economy import RARITIES, GIFT_BGS, GIFT_FXS, GIFT_ANIMS
    if data.rarity not in RARITIES:
        raise HTTPException(status_code=400, detail="Неизвестная редкость")
    for val, allowed_ in ((data.bg, GIFT_BGS), (data.fx, GIFT_FXS), (data.anim, GIFT_ANIMS)):
        if val and val not in allowed_:
            raise HTTPException(status_code=400, detail=f"Неизвестное оформление: {val}")
    if data.sale_from and data.sale_until and as_utc(data.sale_until) <= as_utc(data.sale_from):
        raise HTTPException(status_code=400, detail="Конец продажи должен быть позже начала")
    if data.image_url and not (data.image_url.startswith("/media/")
                               or data.image_url.startswith("https://")):
        raise HTTPException(status_code=400, detail="Картинку нужно загрузить в приложении")


def _apply_gift(row, data: GiftDefIn) -> None:
    row.title = data.title.strip()
    row.emoji = (data.emoji or "🎁").strip() or "🎁"
    row.image_url = data.image_url or None
    row.price = data.price
    row.rarity = data.rarity
    row.supply = data.supply
    row.colors = _clean_colors(data.colors)
    row.sale_from = as_utc(data.sale_from)
    row.sale_until = as_utc(data.sale_until)
    row.active = data.active
    if data.sort is not None:
        row.sort = data.sort
    row.bg = None if data.bg in (None, "", "auto") else data.bg
    row.fx = None if data.fx in (None, "", "auto") else data.fx
    row.anim = None if data.anim in (None, "", "auto") else data.anim
    row.symbol = (data.symbol or "").strip() or None


def _cut_background(raw: bytes) -> tuple[bytes, bool]:
    """Картинка подарка → PNG 512×512 с прозрачным фоном.

    Определяет фоновый цвет по краям изображения и заливкой делает его
    прозрачным, сохраняя детали предмета и сглаживая контуры.
    Возвращает (png, был_ли_убран_фон)."""
    import io
    from collections import deque
    from PIL import Image, ImageFilter, ImageOps

    img = Image.open(io.BytesIO(raw))
    img = ImageOps.exif_transpose(img).convert("RGBA")
    img.thumbnail((768, 768), Image.LANCZOS)
    w, h = img.size
    px = img.load()
    border = [px[x, y] for x in range(w) for y in (0, h - 1)] + \
             [px[x, y] for y in range(h) for x in (0, w - 1)]
    removed = False
    # уже прозрачный по краям — фон не трогаем
    if sum(1 for p in border if p[3] < 200) < len(border) * 0.5:
        rs = sorted(p[0] for p in border)
        gs = sorted(p[1] for p in border)
        bs = sorted(p[2] for p in border)
        m = len(border) // 2
        bg = (rs[m], gs[m], bs[m])
        tol = 42 * 42 * 3

        def near(p):
            return (p[0] - bg[0]) ** 2 + (p[1] - bg[1]) ** 2 + (p[2] - bg[2]) ** 2 <= tol

        mask = bytearray(w * h)          # 1 — фон
        q = deque()
        for x in range(w):
            for y in (0, h - 1):
                if near(px[x, y]) and not mask[y * w + x]:
                    mask[y * w + x] = 1
                    q.append((x, y))
        for y in range(h):
            for x in (0, w - 1):
                if near(px[x, y]) and not mask[y * w + x]:
                    mask[y * w + x] = 1
                    q.append((x, y))
        while q:
            x, y = q.popleft()
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    i = ny * w + nx
                    if not mask[i] and near(px[nx, ny]):
                        mask[i] = 1
                        q.append((nx, ny))
        if sum(mask) > w * h * 0.05:
            removed = True
            alpha = Image.frombytes("L", (w, h), bytes(0 if v else 255 for v in mask))
            alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
            r, g, b, a0 = img.split()
            from PIL import ImageChops
            img = Image.merge("RGBA", (r, g, b, ImageChops.multiply(a0, alpha)))
    # обрезаем пустые края и ставим предмет по центру квадрата
    bbox = img.getchannel("A").point(lambda v: 255 if v > 10 else 0).getbbox()
    if bbox:
        img = img.crop(bbox)
    side = int(max(img.size) * 1.08) or 1
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.size[0]) // 2, (side - img.size[1]) // 2), img)
    canvas = canvas.resize((512, 512), Image.LANCZOS)
    out = io.BytesIO()
    canvas.save(out, "PNG", optimize=True)
    return out.getvalue(), removed


@router.post("/gifts/image")
async def admin_gift_image(file: UploadFile | None = File(default=None),
                           src: str | None = Form(default=None),
                           remove_bg: bool = Form(default=True),
                           admin: User = Depends(require_admin)):
    """Загрузить картинку подарка (или переделать уже загруженную: src=/media/...)."""
    import re
    import uuid
    if file is not None:
        raw = await file.read(20 * 1024 * 1024 + 1)
        if len(raw) > 20 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="Картинка больше 20 МБ")
    elif src and re.fullmatch(r"/media/[A-Za-z0-9_.-]{1,80}", src):
        path = os.path.join("media", src.rsplit("/", 1)[1])
        if not os.path.isfile(path):
            raise HTTPException(status_code=404, detail="Файл не найден")
        with open(path, "rb") as f:
            raw = f.read()
    else:
        raise HTTPException(status_code=400, detail="Нужна картинка")
    try:
        if remove_bg:
            png, removed = _cut_background(raw)
        else:
            from PIL import Image
            import io
            im = Image.open(io.BytesIO(raw)).convert("RGBA")
            im.thumbnail((512, 512), Image.LANCZOS)
            b = io.BytesIO()
            im.save(b, "PNG", optimize=True)
            png, removed = b.getvalue(), False
    except ImportError:
        raise HTTPException(status_code=500,
                            detail="На сервере нет Pillow: pip install pillow")
    except Exception:
        raise HTTPException(status_code=400, detail="Не получилось прочитать картинку")
    os.makedirs("media", exist_ok=True)
    name = f"gift_{uuid.uuid4().hex}.png"
    with open(os.path.join("media", name), "wb") as f:
        f.write(png)
    return {"url": f"/media/{name}", "removed_bg": removed}


@router.get("/gifts")
def admin_gifts(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    from app.models.social import GiftDef
    rows = db.query(GiftDef).order_by(GiftDef.sort.asc(), GiftDef.price.asc()).all()
    return [_gift_admin_dict(db, r) for r in rows]


@router.post("/gifts", status_code=201)
async def admin_create_gift(data: GiftDefIn, db: Session = Depends(get_db),
                            admin: User = Depends(require_admin)):
    import re
    from app.models.social import GiftDef
    from app.routers.economy import invalidate_gifts
    _check_gift(data)
    gid = (data.id or "").strip().lower()
    if gid and not re.fullmatch(r"[a-z0-9_]{2,32}", gid):
        raise HTTPException(status_code=400,
                            detail="ID — латиница, цифры и _ (например halloween_pumpkin)")
    if not gid:
        gid = "g_" + secrets.token_hex(5)
    if db.query(GiftDef).filter(GiftDef.id == gid).first():
        raise HTTPException(status_code=409, detail="Подарок с таким ID уже есть")
    last = db.query(func.max(GiftDef.sort)).scalar() or 0
    row = GiftDef(id=gid, sort=int(last) + 10)
    _apply_gift(row, data)
    db.add(row)
    db.commit()
    db.refresh(row)
    invalidate_gifts()
    return _gift_admin_dict(db, row)


@router.put("/gifts/{gift_id}")
async def admin_update_gift(gift_id: str, data: GiftDefIn, db: Session = Depends(get_db),
                            admin: User = Depends(require_admin)):
    from app.models.social import GiftDef
    from app.routers.economy import invalidate_gifts
    row = db.query(GiftDef).filter(GiftDef.id == gift_id).first()
    if row is None:
        raise HTTPException(status_code=404, detail="Подарок не найден")
    _check_gift(data)
    sold = db.query(UserGift).filter(UserGift.gift_id == gift_id).count()
    if data.supply is not None and data.supply < sold:
        raise HTTPException(status_code=400,
                            detail=f"Уже куплено {sold} — тираж не может быть меньше")
    if sold and row.supply and data.supply is None:
        raise HTTPException(status_code=400,
                            detail="У купленного лимитированного подарка нельзя убрать тираж")
    _apply_gift(row, data)
    db.commit()
    db.refresh(row)
    invalidate_gifts()
    return _gift_admin_dict(db, row)


@router.delete("/gifts/{gift_id}")
async def admin_delete_gift(gift_id: str, db: Session = Depends(get_db),
                            admin: User = Depends(require_admin)):
    """Никто не купил — удаляем совсем; уже есть у людей — только снимаем с продажи."""
    from app.models.social import GiftDef
    from app.routers.economy import invalidate_gifts
    row = db.query(GiftDef).filter(GiftDef.id == gift_id).first()
    if row is None:
        raise HTTPException(status_code=404, detail="Подарок не найден")
    sold = db.query(UserGift).filter(UserGift.gift_id == gift_id).count()
    if sold:
        row.active = False
        db.commit()
        invalidate_gifts()
        return {"deleted": False, "hidden": True}
    db.delete(row)
    db.commit()
    invalidate_gifts()
    return {"deleted": True, "hidden": False}


# ── обновления приложения: загрузить APK / установщик прямо из админки ──

RELEASE_FILE = "app_version.json"
DOWNLOADS = "downloads"
RELEASE_NAMES = {"android": "Connecto.apk", "windows": "Connecto-Setup.exe"}
RELEASE_LIMIT = 600 * 1024 * 1024


def _read_release() -> dict:
    try:
        with open(RELEASE_FILE, "r", encoding="utf-8") as f:
            d = json.load(f)
            return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def _write_release(d: dict) -> None:
    tmp = RELEASE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    os.replace(tmp, RELEASE_FILE)


def _release_view() -> dict:
    d = _read_release()
    files = {}
    for k, name in RELEASE_NAMES.items():
        p = os.path.join(DOWNLOADS, name)
        if os.path.isfile(p):
            st = os.stat(p)
            files[k] = {"size": st.st_size,
                        "uploaded_at": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat()}
    win = d.get("windows") if isinstance(d.get("windows"), dict) else {}
    return {
        "android": {"version": d.get("version"), "build": d.get("build"),
                    "notes": d.get("notes", ""), "mandatory": bool(d.get("mandatory")),
                    "url": d.get("url_direct"), "released_at": d.get("released_at"),
                    "file": files.get("android")},
        "windows": {"version": win.get("version"), "build": win.get("build"),
                    "notes": win.get("notes", ""), "mandatory": bool(win.get("mandatory")),
                    "url": win.get("url"), "released_at": win.get("released_at"),
                    "file": files.get("windows")},
        "history": d.get("history", [])[:20],
    }


@router.get("/release")
def admin_release(admin: User = Depends(require_admin)):
    return _release_view()


@router.post("/release")
async def admin_publish_release(
        platform: str = Form(...),
        version: str = Form(..., max_length=20),
        build: int = Form(..., ge=1, le=1_000_000),
        notes: str = Form(default="", max_length=4000),
        mandatory: bool = Form(default=False),
        file: UploadFile | None = File(default=None),
        admin: User = Depends(require_admin)):
    """Новая версия: файл кладём в downloads/, данные — в app_version.json.
    Без файла — только поправить текст «что нового» у уже выложенной версии."""
    import re
    from app.config import settings
    if platform not in RELEASE_NAMES:
        raise HTTPException(status_code=400, detail="platform: android или windows")
    version = version.strip()
    if not re.fullmatch(r"[0-9][0-9A-Za-z.\-]{0,19}", version):
        raise HTTPException(status_code=400, detail="Версия вида 1.0.1")
    d = _read_release()
    cur = d if platform == "android" else (d.get("windows") if isinstance(d.get("windows"), dict) else {})
    cur_build = int(cur.get("build") or 0)
    name = RELEASE_NAMES[platform]
    now = datetime.now(timezone.utc).isoformat()

    if file is not None:
        if build <= cur_build:
            raise HTTPException(status_code=400,
                                detail=f"Номер сборки должен быть больше текущего ({cur_build})")
        os.makedirs(DOWNLOADS, exist_ok=True)
        tmp = os.path.join(DOWNLOADS, name + ".upload")
        size = 0
        head = b""
        try:
            with open(tmp, "wb") as f:
                while True:
                    chunk = await file.read(1024 * 1024)
                    if not chunk:
                        break
                    if not head:
                        head = chunk[:4]
                    size += len(chunk)
                    if size > RELEASE_LIMIT:
                        raise HTTPException(status_code=413, detail="Файл больше 600 МБ")
                    f.write(chunk)
            # APK — это zip («PK»), установщик Windows — exe («MZ»)
            if platform == "android" and not head.startswith(b"PK"):
                raise HTTPException(status_code=400, detail="Это не APK-файл")
            if platform == "windows" and not head.startswith(b"MZ"):
                raise HTTPException(status_code=400, detail="Это не .exe-установщик")
            if size < 1024 * 1024:
                raise HTTPException(status_code=400, detail="Файл подозрительно маленький")
            os.replace(tmp, os.path.join(DOWNLOADS, name))
        except HTTPException:
            try:
                os.remove(tmp)
            except OSError:
                pass
            raise
        cur_build = build
    elif not cur:
        raise HTTPException(status_code=400, detail="Сначала загрузи файл")

    url = f"{settings.public_base}/download/{name}?b={cur_build}"
    text = notes.strip() or f"Connecto {version}: исправления и улучшения."
    if platform == "android":
        d.update({"build": cur_build, "version": version, "url_direct": url, "notes": text,
                  "mandatory": mandatory})
        d.setdefault("url_telegram", "")
        if file is not None:
            d["released_at"] = now
    else:
        win = dict(cur)
        win.update({"build": cur_build, "version": version, "url": url, "notes": text,
                    "mandatory": mandatory})
        if file is not None:
            win["released_at"] = now
        d["windows"] = win
    if file is not None:
        hist = d.get("history") if isinstance(d.get("history"), list) else []
        hist.insert(0, {"platform": platform, "version": version, "build": cur_build,
                        "notes": text, "at": now,
                        "by": admin.display_name or admin.username})
        d["history"] = hist[:30]
    _write_release(d)
    return _release_view()


@router.get("/mail_check")
def mail_check(send: bool = False, admin: User = Depends(require_admin)):
    """Проверка почты: вход на SMTP и (send=true) тестовое письмо самому админу."""
    from app import email_service
    res = {"status": email_service.check(), "enabled": email_service.enabled()}
    if send and email_service.enabled():
        res["sent"] = email_service._send(admin.email, "Connecto: проверка почты",
                                          "Это тестовое письмо. Если ты его видишь — почта работает.")
    return res
