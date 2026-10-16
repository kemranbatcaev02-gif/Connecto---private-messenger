import uuid
from datetime import datetime, timezone

from sqlalchemy import String, ForeignKey, Text, Integer, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base, UTCDateTime


def _uuid() -> str:
    return str(uuid.uuid4())


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Chat(Base):
    __tablename__ = "chats"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    type: Mapped[str] = mapped_column(String(16))          # direct|group|channel
    title: Mapped[str | None] = mapped_column(String(128), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)
    # ── группы и каналы
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    handle: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)  # публичная ссылка @name
    invite_code: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)
    owner_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    members_can_send: Mapped[bool] = mapped_column(default=True)   # группа: писать могут все
    members_can_add: Mapped[bool] = mapped_column(default=True)    # группа: добавлять могут все
    is_system: Mapped[bool] = mapped_column(default=False)         # чат с ботом Connecto
    is_verified: Mapped[bool] = mapped_column(default=False)       # галочка (выдаёт админ)
    ttl_seconds: Mapped[int] = mapped_column(Integer, default=0)   # автоудаление сообщений


class ChatMember(Base):
    __tablename__ = "chat_members"
    __table_args__ = (Index("ix_chat_members_chat_user", "chat_id", "user_id"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    chat_id: Mapped[str] = mapped_column(String(36), ForeignKey("chats.id"), index=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), index=True)
    role: Mapped[str] = mapped_column(String(16), default="member")   # owner|admin|member
    joined_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)
    # 0 = не заглушён; иначе epoch ms до которого молчим; -1 = навсегда
    muted_until: Mapped[int] = mapped_column(Integer, default=0)
    # «очищено/удалено у себя»: сообщения до этого момента мне не показываются
    cleared_at: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)


class Message(Base):
    __tablename__ = "messages"
    __table_args__ = (Index("ix_messages_chat_created", "chat_id", "created_at"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    chat_id: Mapped[str] = mapped_column(String(36), ForeignKey("chats.id"), index=True)
    sender_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"))
    kind: Mapped[str] = mapped_column(String(16), default="text")   # text|image|video|file|voice|location|contact|service
    text: Mapped[str] = mapped_column(Text, default="")
    media_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    file_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    reply_to_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    forwarded_from: Mapped[str | None] = mapped_column(String(36), nullable=True)
    edited: Mapped[bool] = mapped_column(default=False)
    pinned: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now, index=True)
    # эффект при получении (конфетти, сердца…), тихая отправка
    effect: Mapped[str | None] = mapped_column(String(16), nullable=True)
    silent: Mapped[bool] = mapped_column(default=False)
    # капсула времени: до open_at получатели видят только «запечатанную» капсулу
    open_at: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)
    # исчезающие сообщения: после expires_at сервер удаляет сообщение у всех
    expires_at: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True, index=True)
    # доп. данные (JSON): подарок, ответ на историю
    extra: Mapped[str | None] = mapped_column(Text, nullable=True)
    # сквозное шифрование: конверт {v, sp, c, k:{key_id: ...}} — сервер его не может прочитать
    enc: Mapped[str | None] = mapped_column(Text, nullable=True)


class MessageReaction(Base):
    __tablename__ = "message_reactions"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    message_id: Mapped[str] = mapped_column(String(36), index=True)
    chat_id: Mapped[str] = mapped_column(String(36), index=True)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    emoji: Mapped[str] = mapped_column(String(16))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class ChatRead(Base):
    """До какого момента участник прочитал чат — для галочек ✓✓."""
    __tablename__ = "chat_reads"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    chat_id: Mapped[str] = mapped_column(String(36), ForeignKey("chats.id"), index=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), index=True)
    last_read_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class ChatBan(Base):
    """Исключённый из группы/канала — не может вернуться по ссылке."""
    __tablename__ = "chat_bans"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    chat_id: Mapped[str] = mapped_column(String(36), index=True)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class Block(Base):
    """blocker заблокировал blocked. Заблокированный видит blocker'а скрытым."""
    __tablename__ = "blocks"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    blocker_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), index=True)
    blocked_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class PushToken(Base):
    """FCM-токен устройства пользователя для пушей."""
    __tablename__ = "push_tokens"
    token: Mapped[str] = mapped_column(String(255), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), index=True)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class DeviceKey(Base):
    """Публичный ключ X25519 устройства для сквозного шифрования личных чатов.
    Закрытый ключ хранится только на телефоне."""
    __tablename__ = "device_keys"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)   # key_id
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), index=True)
    device_id: Mapped[str] = mapped_column(String(64), index=True)
    public_key: Mapped[str] = mapped_column(String(128))
    active: Mapped[bool] = mapped_column(default=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class KnownDevice(Base):
    """Доверенное устройство пользователя — с него вход без кода."""
    __tablename__ = "known_devices"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), index=True)
    device_id: Mapped[str] = mapped_column(String(64), index=True)
    name: Mapped[str] = mapped_column(String(64), default="")   # платформа/имя
    city: Mapped[str] = mapped_column(String(128), default="")
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)
    last_login: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class LoginEvent(Base):
    """Журнал входов — для экрана «Входы и устройства»."""
    __tablename__ = "login_events"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), index=True)
    device_id: Mapped[str] = mapped_column(String(64), default="")
    platform: Mapped[str] = mapped_column(String(64), default="")
    city: Mapped[str] = mapped_column(String(128), default="")
    kind: Mapped[str] = mapped_column(String(16), default="login")  # login|new_device
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now, index=True)


class UserSession(Base):
    """Активный сеанс (устройство). Удалили строку — токены сеанса перестают работать."""
    __tablename__ = "sessions"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    device_id: Mapped[str] = mapped_column(String(64), default="")
    platform: Mapped[str] = mapped_column(String(64), default="")
    city: Mapped[str] = mapped_column(String(128), default="")
    ip: Mapped[str] = mapped_column(String(64), default="")
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)
    last_active: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class BotUpdate(Base):
    """Очередь обновлений для бота (getUpdates). id = update_id."""
    __tablename__ = "bot_updates"
    __table_args__ = {"sqlite_autoincrement": True}   # номера никогда не повторяются
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    bot_id: Mapped[str] = mapped_column(String(36), index=True)
    payload: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class PromoCode(Base):
    """Промокод на премиум (создаёт админ)."""
    __tablename__ = "promo_codes"
    code: Mapped[str] = mapped_column(String(32), primary_key=True)
    days: Mapped[int] = mapped_column(Integer, default=30)
    coins: Mapped[int] = mapped_column(Integer, default=0)   # промокод может давать коины
    uses_left: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class PromoUse(Base):
    """Кто уже активировал промокод (один код — один раз на аккаунт)."""
    __tablename__ = "promo_uses"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    code: Mapped[str] = mapped_column(String(32), index=True)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)
