"""Приватность и связи между людьми — применяются на сервере, а не только в UI."""
import json
from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models.user import User
from app.models.chat import Chat, ChatMember, Block

VALUES = ("all", "contacts", "none")
# ключ → значение по умолчанию (как в Telegram: номер и ДР видят контакты)
DEFAULTS = {
    "phone": "contacts",
    "avatar": "all",
    "bio": "all",
    "birthday": "contacts",
    "voice": "all",
    "invites": "all",
    "forwards": "all",
    "stories": "all",     # кто видит мои истории
    "gifts": "all",       # кто видит подарки в профиле
    "calls": "all",       # кто может мне звонить
    "p2p": "all",         # с кем звонок идёт напрямую (иначе — через сервер, IP скрыт)
}
NOTIFY_DEFAULTS = {"private": True, "groups": True, "channels": True,
                   "preview": True, "reactions": True}


def get_privacy(user: User) -> dict:
    data = dict(DEFAULTS)
    try:
        if user.privacy:
            for k, v in json.loads(user.privacy).items():
                if k in DEFAULTS and v in VALUES:
                    data[k] = v
    except Exception:
        pass
    data["lastseen"] = user.lastseen_privacy or "all"
    return data


def set_privacy(user: User, changes: dict) -> dict:
    cur = get_privacy(user)
    for k, v in changes.items():
        if v not in VALUES:
            continue
        if k == "lastseen":
            user.lastseen_privacy = v
        elif k in DEFAULTS:
            cur[k] = v
    user.privacy = json.dumps({k: cur[k] for k in DEFAULTS})
    return get_privacy(user)


def get_notify(user: User) -> dict:
    data = dict(NOTIFY_DEFAULTS)
    try:
        if user.notify:
            for k, v in json.loads(user.notify).items():
                if k in NOTIFY_DEFAULTS:
                    data[k] = bool(v)
    except Exception:
        pass
    return data


def is_blocked(db: Session, blocker_id: str, blocked_id: str) -> bool:
    """True, если blocker_id заблокировал blocked_id."""
    return db.query(Block).filter(
        Block.blocker_id == blocker_id,
        Block.blocked_id == blocked_id).first() is not None


def is_contact(db: Session, a_id: str, b_id: str) -> bool:
    """Контакты = люди, у которых есть общий личный чат (оба в нём)."""
    if a_id == b_id:
        return True
    mine = db.query(ChatMember.chat_id).filter(ChatMember.user_id == a_id)
    row = (db.query(ChatMember)
           .join(Chat, Chat.id == ChatMember.chat_id)
           .filter(Chat.type == "direct", Chat.is_system == False,  # noqa: E712
                   ChatMember.user_id == b_id,
                   ChatMember.chat_id.in_(mine))
           .first())
    return row is not None


def allowed(db: Session, owner: User, viewer_id: str | None, key: str) -> bool:
    """Может ли viewer видеть/делать `key` у owner."""
    if viewer_id is None:
        return False
    if viewer_id == owner.id:
        return True
    if is_blocked(db, owner.id, viewer_id):
        return False
    rule = get_privacy(owner).get(key, "all")
    if rule == "all":
        return True
    if rule == "none":
        return False
    return is_contact(db, owner.id, viewer_id)


def as_utc(dt):
    if dt is None:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def is_premium(user: User | None) -> bool:
    if user is None or user.premium_until is None:
        return False
    return as_utc(user.premium_until) > datetime.now(timezone.utc)


def cover_of(u: User) -> tuple[str | None, str | None]:
    """Обложка с учётом Premium: видео-обложка видна только пока Premium активен."""
    if not u.cover_url:
        return None, None
    kind = u.cover_kind or "image"
    # купленная в магазине видео-обложка работает и без Premium
    if kind == "video" and not is_premium(u) and not getattr(u, "cover_item", None):
        return None, None
    return u.cover_url, kind


PREMIUM_RINGS = {"rainbow", "gold", "aurora"}
FREE_RINGS = {"none", "accent"}


def ring_of(u: User) -> str | None:
    """Рамка аватара для чужих глаз: премиум-рамки — только пока Premium активен."""
    r = getattr(u, "avatar_ring", None)
    if not r:
        return None
    if r in PREMIUM_RINGS:
        return r if is_premium(u) else "accent"
    return r if r in FREE_RINGS else None


def emoji_status_of(u: User) -> str | None:
    return (u.emoji_status or None) if is_premium(u) else None


def public_user(db: Session, u: User, viewer_id: str | None) -> dict:
    """Публичная карточка пользователя с учётом его приватности."""
    hidden = viewer_id is not None and viewer_id != u.id and is_blocked(db, u.id, viewer_id)
    return {
        "id": u.id,
        "username": u.username,
        "handle": u.handle,
        "display_name": u.display_name or u.username,
        "last_name": u.last_name,
        "avatar_url": None if hidden or not allowed(db, u, viewer_id, "avatar") else u.avatar_url,
        "bio": None if hidden or not allowed(db, u, viewer_id, "bio") else u.bio,
        "phone": None if hidden or not allowed(db, u, viewer_id, "phone") else u.phone,
        "birthday": None if hidden or not allowed(db, u, viewer_id, "birthday") else u.birthday,
        "is_bot": bool(u.is_bot),
        "is_verified": bool(u.is_verified),
        "is_premium": is_premium(u),
        "cover_url": None if hidden or not allowed(db, u, viewer_id, "avatar") else cover_of(u)[0],
        "cover_kind": None if hidden or not allowed(db, u, viewer_id, "avatar") else cover_of(u)[1],
        "emoji_status": emoji_status_of(u),
        "avatar_ring": ring_of(u),
        **_worn(db, u, hidden),
    }


def _worn(db: Session, u: User, hidden: bool) -> dict:
    if hidden:
        return {"frame": None, "profile_fx": None}
    from app.routers.shop import worn
    return {"frame": worn(db, getattr(u, "avatar_frame", None)),
            "profile_fx": worn(db, getattr(u, "profile_fx", None))}
