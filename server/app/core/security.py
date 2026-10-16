from datetime import datetime, timedelta, timezone

import bcrypt
from jose import jwt, JWTError

from app.config import settings


# --- Пароли (bcrypt напрямую, без passlib) ---

def hash_password(password: str) -> str:
    # bcrypt работает максимум с 72 байтами пароля
    pw = password.encode("utf-8")[:72]
    return bcrypt.hashpw(pw, bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    pw = password.encode("utf-8")[:72]
    try:
        return bcrypt.checkpw(pw, password_hash.encode("utf-8"))
    except ValueError:
        return False


# --- JWT-токены ---

def _create_token(subject: str, expires_delta: timedelta, token_type: str,
                  sid: str | None = None, extra: dict | None = None) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": subject,
        "type": token_type,
        "iat": now,
        "exp": now + expires_delta,
    }
    if sid:
        payload["sid"] = sid
    if extra:
        payload.update(extra)
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_access_token(subject: str, sid: str | None = None) -> str:
    return _create_token(
        subject,
        timedelta(minutes=settings.access_token_expire_minutes),
        "access", sid,
    )


def create_refresh_token(subject: str, sid: str | None = None) -> str:
    return _create_token(
        subject,
        timedelta(days=settings.refresh_token_expire_days),
        "refresh", sid,
    )


def create_ticket(subject: str, extra: dict, minutes: int = 10) -> str:
    """Короткоживущий билет для шага входа (облачный пароль)."""
    return _create_token(subject, timedelta(minutes=minutes), "ticket",
                         extra=extra)


def decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError:
        return None
