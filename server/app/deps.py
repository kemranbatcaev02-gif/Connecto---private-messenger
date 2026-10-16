from datetime import datetime, timezone, timedelta
from typing import Generator

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.core.security import decode_token
from app.models.user import User
from app.models.chat import UserSession
from app.config import is_admin_email

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _as_utc(dt):
    if dt is None:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def user_from_token(db: Session, token: str) -> User:
    """Проверяет access-токен и сеанс. Бросает 401/403."""
    payload = decode_token(token)
    if payload is None or payload.get("type") != "access":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Недействительный токен")
    user = db.query(User).filter(User.id == payload.get("sub")).first()
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Пользователь не найден")
    if user.is_bot:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Боты входят через Bot API")
    sid = payload.get("sid")
    if sid:
        sess = db.query(UserSession).filter(UserSession.id == sid).first()
        if sess is None or sess.user_id != user.id:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                                detail="Сеанс завершён")
        now = datetime.now(timezone.utc)
        last = _as_utc(sess.last_active)
        if last is None or now - last > timedelta(seconds=60):
            sess.last_active = now
            try:
                db.commit()
            except Exception:
                db.rollback()
    # забаненного пускать нельзя (админа не банят)
    if getattr(user, "banned", False) and not is_admin_email(user.email):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Аккаунт заблокирован")
    user._sid = sid  # текущий сеанс (для «завершить другие»)
    return user


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    return user_from_token(db, token)


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    """Пропускает только админов (email из ADMIN_EMAILS)."""
    if not is_admin_email(current_user.email):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Нужны права администратора",
        )
    return current_user
