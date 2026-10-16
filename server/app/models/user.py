import uuid
from datetime import datetime, timezone

from sqlalchemy import String, Text, Integer
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base, UTCDateTime


def _uuid() -> str:
    return str(uuid.uuid4())


def _now() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    username: Mapped[str] = mapped_column(String(32), unique=True, index=True)      # логин
    handle: Mapped[str | None] = mapped_column(String(32), unique=True, index=True, nullable=True)  # @поиск
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(64))
    last_name: Mapped[str | None] = mapped_column(String(64), nullable=True)
    bio: Mapped[str | None] = mapped_column(String(300), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    birthday: Mapped[str | None] = mapped_column(String(20), nullable=True)   # ISO дата
    avatar_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    lastseen_privacy: Mapped[str] = mapped_column(String(10), default="all")  # all|contacts|none
    banned: Mapped[bool] = mapped_column(default=False)  # заблокирован админом
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)
    last_seen: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)

    # ── приватность (JSON: phone/avatar/bio/birthday/voice/invites/forwards → all|contacts|none)
    privacy: Mapped[str | None] = mapped_column(Text, nullable=True)
    read_receipts: Mapped[bool] = mapped_column(default=True)
    # ── уведомления (JSON: private/groups/channels/preview → bool)
    notify: Mapped[str | None] = mapped_column(Text, nullable=True)

    # ── облачный пароль (двухэтапная проверка)
    cloud_password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    cloud_password_hint: Mapped[str | None] = mapped_column(String(64), nullable=True)

    # ── обложка профиля (1:1): image — всем, video (до 15 с) — только Premium
    cover_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    cover_kind: Mapped[str | None] = mapped_column(String(10), nullable=True)
    # ── эмодзи-статус рядом с именем (Premium)
    emoji_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    # ── рамка аватара (видна всем; премиум-рамки — только пока есть Premium)
    avatar_ring: Mapped[str | None] = mapped_column(String(16), nullable=True)
    # ── надетые предметы из магазина (id товара): обложка, рамка, анимация профиля
    cover_item: Mapped[str | None] = mapped_column(String(48), nullable=True)
    avatar_frame: Mapped[str | None] = mapped_column(String(48), nullable=True)
    profile_fx: Mapped[str | None] = mapped_column(String(48), nullable=True)

    # ── коины (внутренняя валюта) и ежедневный бонус
    coins: Mapped[int] = mapped_column(Integer, default=0)
    daily_streak: Mapped[int] = mapped_column(Integer, default=0)
    daily_last: Mapped[str | None] = mapped_column(String(10), nullable=True)  # YYYY-MM-DD (UTC)

    # ── премиум
    premium_until: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)

    # ── боты
    is_bot: Mapped[bool] = mapped_column(default=False)
    is_verified: Mapped[bool] = mapped_column(default=False)   # галочка (системный бот)
    bot_owner_id: Mapped[str | None] = mapped_column(String(36), nullable=True, index=True)
    bot_token_hash: Mapped[str | None] = mapped_column(String(128), nullable=True)
    bot_webhook: Mapped[str | None] = mapped_column(String(512), nullable=True)
    bot_commands: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON [{command, description}]
