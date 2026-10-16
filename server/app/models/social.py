"""Истории, подарки и внутренняя валюта (коины)."""
import uuid
from datetime import datetime, timezone

from sqlalchemy import String, Text, Integer
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base, UTCDateTime


def _uuid() -> str:
    return str(uuid.uuid4())


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Story(Base):
    """История: живёт expires_at, а если pinned — остаётся в профиле («Публикации»)."""
    __tablename__ = "stories"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    media_url: Mapped[str] = mapped_column(String(512))
    kind: Mapped[str] = mapped_column(String(10), default="image")     # image|video
    caption: Mapped[str] = mapped_column(String(500), default="")
    audience: Mapped[str] = mapped_column(String(10), default="all")   # all|contacts
    pinned: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now, index=True)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime(), index=True)
    deleted_at: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)
    # наложения редактора (JSON: текст, стикеры, погода…) и музыка
    overlays: Mapped[str | None] = mapped_column(Text, nullable=True)
    music_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    music_title: Mapped[str | None] = mapped_column(String(128), nullable=True)


class StoryView(Base):
    __tablename__ = "story_views"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    story_id: Mapped[str] = mapped_column(String(36), index=True)
    viewer_id: Mapped[str] = mapped_column(String(36), index=True)
    reaction: Mapped[str | None] = mapped_column(String(16), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class UserGift(Base):
    """Подарок, который кто-то подарил пользователю."""
    __tablename__ = "user_gifts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    gift_id: Mapped[str] = mapped_column(String(32), index=True)
    from_id: Mapped[str | None] = mapped_column(String(36), nullable=True, index=True)
    to_id: Mapped[str] = mapped_column(String(36), index=True)
    text: Mapped[str] = mapped_column(String(200), default="")
    anonymous: Mapped[bool] = mapped_column(default=False)
    hidden: Mapped[bool] = mapped_column(default=False)       # не показывать в профиле
    converted: Mapped[bool] = mapped_column(default=False)    # обменян на коины
    serial: Mapped[int | None] = mapped_column(Integer, nullable=True)  # № лимитированного
    price: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now, index=True)
    pinned: Mapped[bool] = mapped_column(default=False)           # закреплён сверху в профиле
    # улучшение до уникального: фон, узор и номер среди улучшенных
    upgraded: Mapped[bool] = mapped_column(default=False)
    backdrop: Mapped[str | None] = mapped_column(String(24), nullable=True)
    pattern: Mapped[str | None] = mapped_column(String(24), nullable=True)
    unique_no: Mapped[int | None] = mapped_column(Integer, nullable=True)
    upgrade_cost: Mapped[int] = mapped_column(Integer, default=0)


class CoinTx(Base):
    """Движение коинов: + пополнение/бонус/обмен, − подарки/Premium."""
    __tablename__ = "coin_txs"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    amount: Mapped[int] = mapped_column(Integer)
    kind: Mapped[str] = mapped_column(String(16))
    title: Mapped[str] = mapped_column(String(128), default="")
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now, index=True)


class Payment(Base):
    """Покупка коинов за рубли (ЮKassa)."""
    __tablename__ = "payments"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    package_id: Mapped[str] = mapped_column(String(16))
    coins: Mapped[int] = mapped_column(Integer)
    rub: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(16), default="pending")  # pending|succeeded|canceled
    provider_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    confirmation_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class GiftDef(Base):
    """Подарок в магазине. Добавляется и меняется из админки — без обновления приложения.

    sale_from / sale_until — окно продажи (сезонные подарки, как в Telegram):
    до начала и после конца в магазине его не видно, а у кого он уже есть — остаётся.
    supply — тираж (лимитированный: у каждого купленного свой номер).
    """
    __tablename__ = "gift_defs"
    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    title: Mapped[str] = mapped_column(String(64))
    emoji: Mapped[str] = mapped_column(String(16), default="🎁")
    image_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    price: Mapped[int] = mapped_column(Integer, default=10)
    rarity: Mapped[str] = mapped_column(String(12), default="common")  # common|rare|epic|legendary
    supply: Mapped[int | None] = mapped_column(Integer, nullable=True)
    colors: Mapped[str | None] = mapped_column(String(64), nullable=True)  # "#FF8A00,#7C2D12"
    sale_from: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)
    sale_until: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)
    active: Mapped[bool] = mapped_column(default=True)
    sort: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)
    # оформление: фон плашки, эффект частиц, анимация предмета (пусто — как раньше по редкости)
    bg: Mapped[str | None] = mapped_column(String(24), nullable=True)
    fx: Mapped[str | None] = mapped_column(String(24), nullable=True)
    anim: Mapped[str | None] = mapped_column(String(16), nullable=True)
    symbol: Mapped[str | None] = mapped_column(String(16), nullable=True)  # для эффекта «float»


class ShopItem(Base):
    """Товар магазина оформления. Добавляется из админки (по одному или паком-архивом).

    kind: cover — обложка профиля, frame — рамка аватара, effect — анимация поверх профиля,
    wallpaper — обои чата. media_kind: image (в т.ч. анимированный webp/gif) | video (mp4).
    price 0 — бесплатно. discount — скидка в % (до discount_until, если задано).
    """
    __tablename__ = "shop_items"
    id: Mapped[str] = mapped_column(String(48), primary_key=True)
    kind: Mapped[str] = mapped_column(String(16), index=True)
    title: Mapped[str] = mapped_column(String(64))
    description: Mapped[str] = mapped_column(String(300), default="")
    price: Mapped[int] = mapped_column(Integer, default=0)
    discount: Mapped[int] = mapped_column(Integer, default=0)
    discount_until: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)
    premium_free: Mapped[bool] = mapped_column(default=False)   # бесплатно с Premium
    premium_only: Mapped[bool] = mapped_column(default=False)   # купить можно только с Premium
    rarity: Mapped[str] = mapped_column(String(12), default="common")
    collection: Mapped[str | None] = mapped_column(String(48), nullable=True, index=True)
    tags: Mapped[str] = mapped_column(String(256), default="")
    media_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    media_kind: Mapped[str] = mapped_column(String(10), default="image")
    preview_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    colors: Mapped[str | None] = mapped_column(String(64), nullable=True)
    supply: Mapped[int | None] = mapped_column(Integer, nullable=True)
    sale_from: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)
    sale_until: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)
    active: Mapped[bool] = mapped_column(default=True)
    featured: Mapped[bool] = mapped_column(default=False)
    sort: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class ShopCollection(Base):
    """Коллекция (Хэллоуин, Космос…): баннер на главной магазина и своя подборка."""
    __tablename__ = "shop_collections"
    id: Mapped[str] = mapped_column(String(48), primary_key=True)
    title: Mapped[str] = mapped_column(String(64))
    subtitle: Mapped[str] = mapped_column(String(160), default="")
    banner_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    banner_kind: Mapped[str] = mapped_column(String(10), default="image")
    colors: Mapped[str | None] = mapped_column(String(64), nullable=True)
    sale_from: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)
    sale_until: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)
    active: Mapped[bool] = mapped_column(default=True)
    featured: Mapped[bool] = mapped_column(default=True)
    sort: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)


class UserItem(Base):
    """Предмет в инвентаре. source: buy | free | gift | admin."""
    __tablename__ = "user_items"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    item_id: Mapped[str] = mapped_column(String(48), index=True)
    source: Mapped[str] = mapped_column(String(10), default="buy")
    price: Mapped[int] = mapped_column(Integer, default=0)
    from_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=_now)
