from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.deps import get_db, get_current_user
from app.models.user import User
from app.models.chat import KnownDevice, LoginEvent, UserSession
from app.schemas.user import UserCreate
from app.core.security import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token,
    create_ticket,
    decode_token,
)
from app import email_service, verify, geoip, sysbot
from app.users_out import me_dict

router = APIRouter(prefix="/auth", tags=["auth"])


# ── вспомогательные ──

def _now():
    return datetime.now(timezone.utc)


def _client_ip(request: Request) -> str:
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else ""


def _mask_email(email: str) -> str:
    try:
        name, dom = email.split("@", 1)
        if len(name) <= 2:
            masked = name[0] + "*"
        else:
            masked = name[0] + "*" * (len(name) - 2) + name[-1]
        return f"{masked}@{dom}"
    except Exception:
        return email


def _issue(db: Session, user: User, device_id: str | None, platform: str | None,
           city: str, ip: str, alert: bool) -> dict:
    """Создаёт сеанс, доверяет устройству, пишет в журнал, отдаёт токены."""
    dev = (device_id or "")[:64]
    plat = (platform or "")[:64]
    if dev:
        kd = (db.query(KnownDevice)
              .filter(KnownDevice.user_id == user.id, KnownDevice.device_id == dev).first())
        if kd is None:
            db.add(KnownDevice(user_id=user.id, device_id=dev, name=plat, city=city))
        else:
            kd.last_login = _now()
            kd.city = city or kd.city
        # один сеанс на устройство
        db.query(UserSession).filter(UserSession.user_id == user.id,
                                     UserSession.device_id == dev).delete()
    sess = UserSession(user_id=user.id, device_id=dev, platform=plat, city=city, ip=ip)
    db.add(sess)
    db.add(LoginEvent(user_id=user.id, device_id=dev, platform=plat, city=city,
                      kind="new_device" if alert else "login"))
    db.commit()
    db.refresh(sess)
    if alert:
        try:
            sysbot.post(db, user, sysbot.login_alert_text(plat, city))
        except Exception:
            pass
    return {
        "access_token": create_access_token(user.id, sess.id),
        "refresh_token": create_refresh_token(user.id, sess.id),
        "token_type": "bearer",
        "user": me_dict(db, user),
    }


def _find_user(db: Session, login: str) -> User | None:
    login = (login or "").strip()
    return (db.query(User)
            .filter(or_(User.username == login, User.email == login,
                        User.email == login.lower(),
                        User.handle == login.lstrip("@")))
            .filter(User.is_bot == False)  # noqa: E712
            .first())


def _auth_user(db: Session, login: str, password: str) -> User:
    key = "login:" + (login or "").strip().lower()
    if verify.too_many(key):
        raise HTTPException(status_code=429,
                            detail="Слишком много попыток. Подожди 15 минут.")
    user = _find_user(db, login)
    if user is None or not verify_password(password, user.password_hash):
        verify.fail(key)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Неверный логин или пароль")
    from app.config import is_admin_email
    if getattr(user, "banned", False) and not is_admin_email(user.email):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Аккаунт заблокирован")
    verify.reset(key)
    return user


def _complete(db: Session, user: User, data, request: Request, new_device: bool) -> dict:
    """После проверки пароля (и кода): спросить облачный пароль или выдать токены."""
    city = geoip.city_by_ip(_client_ip(request))
    if new_device and user.cloud_password_hash:
        ticket = create_ticket(user.id, {"dev": data.device_id or "",
                                         "plat": data.platform or ""})
        return {"needs_password": True, "ticket": ticket,
                "hint": user.cloud_password_hint or ""}
    return _issue(db, user, data.device_id, data.platform, city,
                  _client_ip(request), alert=new_device)


def _is_known(db: Session, user: User, device_id: str | None) -> bool:
    if not device_id:
        return False
    return db.query(KnownDevice).filter(KnownDevice.user_id == user.id,
                                        KnownDevice.device_id == device_id).first() is not None


# ── регистрация: сначала код на почту, потом создание аккаунта ──

class RegisterCodeIn(BaseModel):
    email: EmailStr
    username: str = Field(min_length=3, max_length=32, pattern=r"^[a-zA-Z0-9_]+$")


def _taken(db: Session, username: str, email: str) -> str | None:
    if db.query(User).filter(User.email == email).first():
        return "Эта почта уже привязана к другому аккаунту"
    if db.query(User).filter(or_(User.username == username, User.handle == username)).first():
        return "Этот логин уже занят"
    return None


@router.post("/register/code")
def register_code(data: RegisterCodeIn, db: Session = Depends(get_db)):
    """Шаг 1 регистрации: проверяем, что логин и почта свободны, и шлём код."""
    email = data.email.strip().lower()
    err = _taken(db, data.username, email)
    if err:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=err)
    if not email_service.enabled():
        return {"sent": False, "required": False}
    key = "regsend:" + email
    if verify.too_many(key):
        raise HTTPException(status_code=429,
                            detail="Слишком много писем. Подожди 15 минут.")
    verify.fail(key)
    code = verify.gen_and_store("reg:" + email)
    if not email_service.send_code(email, code):
        raise HTTPException(status_code=503,
                            detail="Не удалось отправить письмо. Проверь почту и попробуй ещё раз.")
    return {"sent": True, "required": True, "email_masked": _mask_email(email)}


@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(data: UserCreate, request: Request, db: Session = Depends(get_db)):
    email = data.email.strip().lower()
    err = _taken(db, data.username, email)
    if err:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=err)
    # почта подтверждается кодом (если отправка писем настроена на сервере)
    if email_service.enabled():
        if not data.code:
            raise HTTPException(status_code=400, detail="Введи код из письма")
        if not verify.check("reg:" + email, data.code):
            raise HTTPException(status_code=400, detail="Неверный или истёкший код из письма")
        verify.reset("regsend:" + email)
    user = User(username=data.username, email=email,
                password_hash=hash_password(data.password),
                display_name=data.display_name)
    db.add(user)
    db.commit()
    db.refresh(user)
    city = geoip.city_by_ip(_client_ip(request))
    out = _issue(db, user, data.device_id, data.platform, city, _client_ip(request),
                 alert=False)
    try:
        sysbot.post(db, user, sysbot.WELCOME)
    except Exception:
        pass
    return out


# ── вход ──

class LoginData(BaseModel):
    login: str
    password: str
    device_id: str | None = None
    platform: str | None = None


class LoginVerifyData(LoginData):
    code: str


@router.post("/login")
def login(data: LoginData, request: Request, db: Session = Depends(get_db)):
    """Шаг 1. С доверенного устройства — сразу токены. С нового — код на почту."""
    user = _auth_user(db, data.login, data.password)
    known = _is_known(db, user, data.device_id)
    if known:
        return _complete(db, user, data, request, new_device=False)
    if not email_service.enabled():
        # почта не настроена — кода нет, но облачный пароль всё равно спросим
        return _complete(db, user, data, request, new_device=True)
    code = verify.gen_and_store("login:" + user.email)
    city = geoip.city_by_ip(_client_ip(request))
    has_sessions = db.query(UserSession).filter(UserSession.user_id == user.id).count() > 0
    to_chat = False
    to_mail = False
    if has_sessions:
        to_chat = _login_code_to_chat(db, user, code, city, data.platform or "")
    if not to_chat:
        to_mail = email_service.send_login_code(user.email, code, city, data.platform or "")
    if not to_mail and not to_chat:
        raise HTTPException(status_code=503,
                            detail="Не удалось отправить код подтверждения. Попробуй через минуту "
                                   "или напиши в поддержку.")
    return {
        "needs_code": True,
        "email_masked": _mask_email(user.email),
        "sent_to_email": to_mail,
        "sent_to_chat": to_chat,
        "has_active_sessions": has_sessions,
        "has_cloud_password": bool(user.cloud_password_hash),
        "cloud_password_hint": user.cloud_password_hint or "",
    }


def _login_code_to_chat(db: Session, user: User, code: str, city: str, platform: str) -> bool:
    """Код входа — сообщением от Connecto, если аккаунт открыт ещё где-то."""
    from app.models.chat import UserSession
    if db.query(UserSession).filter(UserSession.user_id == user.id).count() == 0:
        return False
    try:
        where = f" ({city})" if city else ""
        sysbot.post(db, user, f"🔑 Код для входа: {code}\n\nВход с устройства {platform or 'неизвестно'}"
                              f"{where}. Никому не сообщайте этот код. Если это не вы — "
                              f"смените пароль в Настройки → Безопасность.")
        return True
    except Exception as e:  # noqa: BLE001
        print("login code to chat failed:", repr(e), flush=True)
        return False


class LoginEmailData(BaseModel):
    login: str
    password: str
    device_id: str | None = None
    platform: str | None = None


@router.post("/login/send-email")
def login_send_email(data: LoginEmailData, request: Request, db: Session = Depends(get_db)):
    """Отправить код подтверждения на почту (альтернатива коду на устройстве)."""
    user = _auth_user(db, data.login, data.password)
    code = verify.gen_and_store("login:" + user.email)
    city = geoip.city_by_ip(_client_ip(request))
    sent = email_service.send_login_code(user.email, code, city, data.platform or "")
    if not sent:
        raise HTTPException(status_code=503, detail="Не удалось отправить код на почту. Проверьте настройки почты.")
    return {"ok": True, "email_masked": _mask_email(user.email), "sent_to_email": True}


class LoginCloudPassData(BaseModel):
    login: str
    password: str
    cloud_password: str
    device_id: str | None = None
    platform: str | None = None


@router.post("/login/cloud-password")
def login_cloud_password(data: LoginCloudPassData, request: Request, db: Session = Depends(get_db)):
    """Вход с помощью облачного пароля (в обход одноразового кода)."""
    from app.core.security import verify_password
    user = _auth_user(db, data.login, data.password)
    if not user.cloud_password_hash:
        raise HTTPException(status_code=400, detail="Облачный пароль не установлен")
    key = "2fa:" + user.id
    if verify.too_many(key):
        raise HTTPException(status_code=429, detail="Слишком много попыток. Подожди 5 минут")
    if not verify_password(data.cloud_password, user.cloud_password_hash):
        verify.record_attempt(key)
        raise HTTPException(status_code=400, detail="Неверный облачный пароль")
    verify.reset(key)
    city = geoip.city_by_ip(_client_ip(request))
    return _issue(db, user, data.device_id, data.platform, city, _client_ip(request), alert=True)


@router.post("/login/verify")
def login_verify(data: LoginVerifyData, request: Request, db: Session = Depends(get_db)):
    """Шаг 2. Код с почты → токены (или шаг облачного пароля)."""
    user = _auth_user(db, data.login, data.password)
    if not verify.check("login:" + user.email, data.code):
        raise HTTPException(status_code=400, detail="Неверный или истёкший код")
    return _complete(db, user, data, request, new_device=True)


class TicketData(BaseModel):
    ticket: str
    password: str | None = None
    code: str | None = None


def _ticket_user(db: Session, ticket: str) -> tuple[User, dict]:
    p = decode_token(ticket)
    if not p or p.get("type") != "ticket":
        raise HTTPException(status_code=401, detail="Время входа истекло, начни заново")
    user = db.query(User).filter(User.id == p.get("sub")).first()
    if user is None:
        raise HTTPException(status_code=401, detail="Пользователь не найден")
    return user, p


@router.post("/login/2fa")
def login_2fa(data: TicketData, request: Request, db: Session = Depends(get_db)):
    """Шаг 3. Облачный пароль."""
    user, p = _ticket_user(db, data.ticket)
    key = "2fa:" + user.id
    if verify.too_many(key):
        raise HTTPException(status_code=429, detail="Слишком много попыток. Подожди 15 минут.")
    if not user.cloud_password_hash or not verify_password(data.password or "", user.cloud_password_hash):
        verify.fail(key)
        raise HTTPException(status_code=401, detail="Неверный облачный пароль")
    verify.reset(key)
    city = geoip.city_by_ip(_client_ip(request))
    return _issue(db, user, p.get("dev"), p.get("plat"), city, _client_ip(request), alert=True)


@router.post("/login/2fa/forgot")
def login_2fa_forgot(data: TicketData, db: Session = Depends(get_db)):
    user, _ = _ticket_user(db, data.ticket)
    code = verify.gen_and_store("2fareset:" + user.email)
    if not email_service.send_2fa_reset_code(user.email, code):
        raise HTTPException(status_code=503, detail="Не удалось отправить письмо")
    return {"sent": True, "email_masked": _mask_email(user.email)}


@router.post("/login/2fa/reset")
def login_2fa_reset(data: TicketData, request: Request, db: Session = Depends(get_db)):
    user, p = _ticket_user(db, data.ticket)
    if not verify.check("2fareset:" + user.email, data.code):
        raise HTTPException(status_code=400, detail="Неверный или истёкший код")
    user.cloud_password_hash = None
    user.cloud_password_hint = None
    db.commit()
    city = geoip.city_by_ip(_client_ip(request))
    return _issue(db, user, p.get("dev"), p.get("plat"), city, _client_ip(request), alert=True)


# ── сброс основного пароля ──

class ForgotData(BaseModel):
    email: EmailStr


class ResetData(BaseModel):
    email: EmailStr
    code: str
    new_password: str = Field(min_length=8, max_length=128)


@router.post("/password/forgot")
def password_forgot(data: ForgotData, db: Session = Depends(get_db)):
    email = data.email.strip().lower()
    user = db.query(User).filter(User.email == email, User.is_bot == False).first()  # noqa: E712
    if user is not None:
        code = verify.gen_and_store("reset:" + email)
        if not email_service.send_reset_code(email, code):
            raise HTTPException(status_code=503, detail="Не удалось отправить письмо")
    # не раскрываем, есть ли такая почта
    return {"sent": True}


@router.post("/password/reset")
def password_reset(data: ResetData, db: Session = Depends(get_db)):
    email = data.email.strip().lower()
    if not verify.check("reset:" + email, data.code):
        raise HTTPException(status_code=400, detail="Неверный или истёкший код")
    user = db.query(User).filter(User.email == email).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Аккаунт не найден")
    user.password_hash = hash_password(data.new_password)
    # выходим на всех устройствах
    db.query(UserSession).filter(UserSession.user_id == user.id).delete()
    db.commit()
    return {"ok": True}


# ── токены и выход ──

class RefreshData(BaseModel):
    refresh_token: str


@router.post("/refresh")
def refresh(data: RefreshData, request: Request, db: Session = Depends(get_db)):
    p = decode_token(data.refresh_token)
    if not p or p.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Недействительный токен")
    user = db.query(User).filter(User.id == p.get("sub")).first()
    if user is None or user.is_bot:
        raise HTTPException(status_code=401, detail="Пользователь не найден")
    sid = p.get("sid")
    sess = db.query(UserSession).filter(UserSession.id == sid).first() if sid else None
    if sess is None or sess.user_id != user.id:
        raise HTTPException(status_code=401, detail="Сеанс завершён")
    sess.last_active = _now()
    db.commit()
    return {
        "access_token": create_access_token(user.id, sess.id),
        "refresh_token": create_refresh_token(user.id, sess.id),
        "token_type": "bearer",
    }


class LegacyUpgrade(BaseModel):
    device_id: str | None = None
    platform: str | None = None


@router.post("/session")
def upgrade_legacy(data: LegacyUpgrade, request: Request, db: Session = Depends(get_db),
                   current_user: User = Depends(get_current_user)):
    """Старый токен без сеанса → создать сеанс (после обновления приложения)."""
    if getattr(current_user, "_sid", None):
        raise HTTPException(status_code=400, detail="Сеанс уже есть")
    city = geoip.city_by_ip(_client_ip(request))
    return _issue(db, current_user, data.device_id, data.platform, city,
                  _client_ip(request), alert=False)


@router.post("/logout", status_code=204)
def logout(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    sid = getattr(current_user, "_sid", None)
    if sid:
        db.query(UserSession).filter(UserSession.id == sid).delete()
        db.commit()


@router.get("/login_events")
def login_events(db: Session = Depends(get_db),
                 current_user: User = Depends(get_current_user)):
    rows = (db.query(LoginEvent)
            .filter(LoginEvent.user_id == current_user.id)
            .order_by(LoginEvent.created_at.desc())
            .limit(30).all())
    return [{
        "platform": r.platform,
        "city": r.city,
        "kind": r.kind,
        "created_at": r.created_at.isoformat() if r.created_at else None,
    } for r in rows]


# ── вход по QR-коду (компьютер показывает код, телефон подтверждает) ──

import secrets as _secrets  # noqa: E402
import time as _time  # noqa: E402

QR_TTL = 120
_QR_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # без 0/O и 1/I — чтобы не путать
_QR: dict[str, dict] = {}        # token → запрос входа
_QR_CODES: dict[str, str] = {}   # короткий код → token


def _qr_cleanup() -> None:
    now = _time.time()
    for t in [t for t, q in _QR.items() if now - q["created"] > QR_TTL + 60]:
        q = _QR.pop(t, None)
        if q:
            _QR_CODES.pop(q["code"], None)


def _qr_by(token: str | None, code: str | None) -> dict | None:
    _qr_cleanup()
    if code and not token:
        token = _QR_CODES.get(code.strip().upper().replace("-", "").replace(" ", ""))
    q = _QR.get(token or "")
    if q is None or _time.time() - q["created"] > QR_TTL:
        return None
    return q


class QrStart(BaseModel):
    device_id: str | None = Field(default=None, max_length=64)
    platform: str | None = Field(default=None, max_length=64)


@router.post("/qr/start")
def qr_start(data: QrStart, request: Request):
    """Новое устройство (обычно компьютер) просит QR-код для входа."""
    _qr_cleanup()
    if len(_QR) > 5000:
        raise HTTPException(status_code=429, detail="Слишком много запросов, попробуй позже")
    token = _secrets.token_urlsafe(24)
    code = "".join(_secrets.choice(_QR_ALPHABET) for _ in range(8))
    ip = _client_ip(request)
    _QR[token] = {"token": token, "code": code, "created": _time.time(),
                  "device_id": (data.device_id or "")[:64],
                  "platform": (data.platform or "Компьютер")[:64],
                  "ip": ip, "city": geoip.city_by_ip(ip),
                  "status": "pending", "result": None}
    _QR_CODES[code] = token
    return {"token": token, "code": code, "qr": f"connecto-login:{token}",
            "expires_in": QR_TTL}


@router.get("/qr/{token}")
def qr_poll(token: str):
    """Компьютер спрашивает: подтвердили ли вход на телефоне?"""
    q = _QR.get(token)
    if q is None or _time.time() - q["created"] > QR_TTL:
        return {"status": "expired"}
    if q["status"] != "approved":
        return {"status": q["status"]}
    # отдаём токены один раз
    _QR.pop(token, None)
    _QR_CODES.pop(q["code"], None)
    return {"status": "approved", **(q["result"] or {})}


class QrRef(BaseModel):
    token: str | None = Field(default=None, max_length=128)
    code: str | None = Field(default=None, max_length=16)


def _qr_for_user(data: QrRef, user: User) -> dict:
    key = "qr:" + user.id
    if verify.too_many(key):
        raise HTTPException(status_code=429, detail="Слишком много попыток. Подожди 15 минут.")
    q = _qr_by(data.token, data.code)
    if q is None or q["status"] == "approved":
        verify.fail(key)
        raise HTTPException(status_code=404,
                            detail="Код не найден или устарел. Обнови QR на компьютере.")
    return q


@router.post("/qr/inspect")
def qr_inspect(data: QrRef, user: User = Depends(get_current_user)):
    """Телефон отсканировал код: показываем, куда именно будет вход."""
    q = _qr_for_user(data, user)
    q["status"] = "scanned"
    return {"platform": q["platform"], "city": q["city"], "ip": q["ip"]}


@router.post("/qr/approve")
def qr_approve(data: QrRef, db: Session = Depends(get_db),
               user: User = Depends(get_current_user)):
    """Телефон подтвердил — компьютер получит вход при следующем опросе."""
    q = _qr_for_user(data, user)
    if user.cloud_password_hash:
        # облачный пароль всё равно спросим на компьютере
        ticket = create_ticket(user.id, {"dev": q["device_id"], "plat": q["platform"]})
        q["result"] = {"needs_password": True, "ticket": ticket,
                       "hint": user.cloud_password_hint or ""}
    else:
        q["result"] = _issue(db, user, q["device_id"], q["platform"], q["city"], q["ip"],
                             alert=True)
    q["status"] = "approved"
    verify.reset("qr:" + user.id)
    return {"ok": True, "platform": q["platform"], "city": q["city"]}
