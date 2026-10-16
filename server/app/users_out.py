"""Как отдавать «себя» клиенту (профиль + настройки)."""
from sqlalchemy.orm import Session

from app.models.user import User
from app.config import is_admin_email
from app.privacy import (get_privacy, get_notify, is_premium, as_utc, cover_of,
                         emoji_status_of, ring_of)


def me_dict(db: Session, u: User) -> dict:
    pu = as_utc(u.premium_until)
    return {
        "id": u.id,
        "username": u.username,
        "handle": u.handle,
        "email": u.email,
        "display_name": u.display_name,
        "last_name": u.last_name,
        "bio": u.bio,
        "phone": u.phone,
        "birthday": u.birthday,
        "avatar_url": u.avatar_url,
        "lastseen_privacy": u.lastseen_privacy or "all",
        "banned": bool(u.banned),
        "is_admin": is_admin_email(u.email),
        "is_premium": is_premium(u),
        "is_verified": bool(u.is_verified),
        "premium_until": pu.isoformat() if pu else None,
        "has_cloud_password": bool(u.cloud_password_hash),
        "cloud_password_hint": u.cloud_password_hint,
        "read_receipts": bool(u.read_receipts) if u.read_receipts is not None else True,
        "privacy": get_privacy(u),
        "notify": get_notify(u),
        "created_at": u.created_at.isoformat() if u.created_at else None,
        "cover_url": cover_of(u)[0],
        "cover_kind": cover_of(u)[1],
        "emoji_status": emoji_status_of(u),
        "coins": int(u.coins or 0),
        "avatar_ring": u.avatar_ring,
        "avatar_ring_effective": ring_of(u),
        **worn_dict(db, u),
    }


def worn_dict(db: Session, u: User) -> dict:
    """Надетые предметы магазина: рамка аватара и анимация профиля (видны всем)."""
    from app.routers.shop import worn
    return {"frame": worn(db, getattr(u, "avatar_frame", None)),
            "profile_fx": worn(db, getattr(u, "profile_fx", None)),
            "cover_item": getattr(u, "cover_item", None)}
