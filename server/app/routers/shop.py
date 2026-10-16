"""Магазин оформления: обложки, рамки аватара, анимации профиля, обои чата.

Товары и коллекции живут в базе и полностью управляются из админки — по одному
(Админ-панель → Магазин) или паком: zip-архив с shop.json и медиафайлами
(POST /admin/shop/import). Приложение обновлять не нужно.

Формат shop.json:
{
  "collections": [{"id": "halloween", "title": "Хэллоуин", "subtitle": "...",
                   "banner": "hw_banner.mp4", "colors": ["#FF7A00", "#1A0B2E"],
                   "sale_until": "2026-11-01T21:00:00Z"}],
  "items": [{"id": "cv_hw_moon", "kind": "cover", "title": "Кровавая луна", "price": 150,
             "discount": 20, "rarity": "epic", "collection": "halloween",
             "media": "cv_hw_moon.mp4", "preview": "cv_hw_moon.jpg", "tags": "луна ночь"}],
  "gifts": [{"id": "hw_pumpkin", "title": "Тыква", "price": 50, "rarity": "rare",
             "image": "hw_pumpkin.png", "sale_until": "2026-11-01T21:00:00Z"}]
}
"""
import io
import json
import os
import re
import shutil
import subprocess
import time
import uuid
import zipfile
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.deps import get_current_user, get_db, require_admin
from app.models.user import User
from app.models.social import GiftDef, ShopCollection, ShopItem, UserItem
from app.privacy import as_utc, is_blocked, is_premium

router = APIRouter(tags=["shop"])
admin_router = APIRouter(prefix="/admin/shop", tags=["admin"])

KINDS = ("cover", "frame", "effect", "wallpaper")
KIND_TITLES = {"cover": "Обложки", "frame": "Рамки", "effect": "Анимации",
               "wallpaper": "Обои"}
RARITIES = ("common", "rare", "epic", "legendary")
MEDIA_KINDS = ("image", "video")
SORTS = ("popular", "new", "price_asc", "price_desc", "discount")
FILTERS = ("free", "sale", "owned", "premium", "limited", "new")
NEW_DAYS = 14
SHOP_DIR = os.path.join("media", "shop")
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".gif"}
VIDEO_EXT = {".mp4", ".webm", ".mov"}
MAX_MEDIA = 80 * 1024 * 1024
MAX_PACK = 600 * 1024 * 1024
_ID = re.compile(r"[a-z0-9_]{2,48}")


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── кэш каталога (читается на каждом открытии профиля) ──
_CACHE: dict | None = None
_CACHE_AT = 0.0
_TTL = 15.0


def invalidate() -> None:
    global _CACHE
    _CACHE = None


def _rows(db: Session) -> dict:
    global _CACHE, _CACHE_AT
    t = time.monotonic()
    if _CACHE is None or t - _CACHE_AT > _TTL:
        items = db.query(ShopItem).order_by(ShopItem.sort.asc(), ShopItem.created_at.desc()).all()
        cols = db.query(ShopCollection).order_by(ShopCollection.sort.asc()).all()
        sold = dict(db.query(UserItem.item_id, func.count(UserItem.id))
                    .group_by(UserItem.item_id).all())
        _CACHE = {
            "items": {i.id: _snap(i) for i in items},
            "order": [i.id for i in items],
            "cols": {c.id: _col_snap(c) for c in cols},
            "col_order": [c.id for c in cols],
            "sold": sold,
        }
        _CACHE_AT = t
    return _CACHE


def _colors(s: str | None) -> list[str]:
    return [c for c in (s or "").split(",") if c][:3]


def _snap(i: ShopItem) -> dict:
    return {
        "id": i.id, "kind": i.kind, "title": i.title, "description": i.description or "",
        "price": int(i.price or 0), "discount": int(i.discount or 0),
        "discount_until": as_utc(i.discount_until), "premium_free": bool(i.premium_free),
        "premium_only": bool(i.premium_only), "rarity": i.rarity or "common",
        "collection": i.collection, "tags": i.tags or "", "media_url": i.media_url,
        "media_kind": i.media_kind or "image", "preview_url": i.preview_url,
        "colors": _colors(i.colors), "supply": i.supply, "sale_from": as_utc(i.sale_from),
        "sale_until": as_utc(i.sale_until), "active": bool(i.active),
        "featured": bool(i.featured), "sort": i.sort or 0, "created_at": as_utc(i.created_at),
    }


def _col_snap(c: ShopCollection) -> dict:
    return {
        "id": c.id, "title": c.title, "subtitle": c.subtitle or "", "banner_url": c.banner_url,
        "banner_kind": c.banner_kind or "image", "colors": _colors(c.colors),
        "sale_from": as_utc(c.sale_from), "sale_until": as_utc(c.sale_until),
        "active": bool(c.active), "featured": bool(c.featured), "sort": c.sort or 0,
    }


def status_of(s: dict, now: datetime | None = None) -> str:
    """on_sale | soon | ended | off — для товаров и коллекций одинаково."""
    now = now or _now()
    if not s["active"]:
        return "off"
    if s["sale_from"] and now < s["sale_from"]:
        return "soon"
    if s["sale_until"] and now >= s["sale_until"]:
        return "ended"
    return "on_sale"


def item_snapshot(db: Session, item_id: str | None) -> dict | None:
    """Товар по id (даже снятый с продажи — у владельцев он должен работать)."""
    if not item_id:
        return None
    return _rows(db)["items"].get(item_id)


def worn(db: Session, item_id: str | None) -> dict | None:
    """Надетый предмет так, как его рисуют профили: {id, url, kind, title}."""
    s = item_snapshot(db, item_id)
    if s is None or not s["media_url"]:
        return None
    return {"id": s["id"], "url": s["media_url"], "kind": s["media_kind"], "title": s["title"]}


def _iso(d: datetime | None) -> str | None:
    return d.isoformat() if d else None


def discount_now(s: dict, now: datetime | None = None) -> int:
    now = now or _now()
    d = int(s["discount"] or 0)
    if d <= 0 or (s["discount_until"] and now >= s["discount_until"]):
        return 0
    return min(d, 95)


def final_price(s: dict, now: datetime | None = None) -> int:
    d = discount_now(s, now)
    return int(round(s["price"] * (100 - d) / 100)) if d else int(s["price"])


def price_for(s: dict, user: User, now: datetime | None = None) -> int:
    if s["premium_free"] and is_premium(user):
        return 0
    return final_price(s, now)


def item_out(s: dict, me: User, owned: set[str], equipped: set[str], sold: dict,
             cols: dict, now: datetime) -> dict:
    left = None
    if s["supply"]:
        left = max(0, int(s["supply"]) - int(sold.get(s["id"], 0)))
    disc = discount_now(s, now)
    col = cols.get(s["collection"] or "")
    return {
        "id": s["id"], "kind": s["kind"], "title": s["title"], "description": s["description"],
        "price": s["price"], "final_price": final_price(s, now), "my_price": price_for(s, me, now),
        "discount": disc, "discount_until": _iso(s["discount_until"]) if disc else None,
        "free": final_price(s, now) == 0, "premium_free": s["premium_free"],
        "premium_only": s["premium_only"], "rarity": s["rarity"],
        "collection": s["collection"], "collection_title": col["title"] if col else None,
        "media_url": s["media_url"], "media_kind": s["media_kind"],
        "preview_url": s["preview_url"] or (s["media_url"] if s["media_kind"] == "image" else None),
        "colors": s["colors"], "supply": s["supply"], "left": left,
        "sold": int(sold.get(s["id"], 0)),
        "sale_until": _iso(s["sale_until"]), "status": status_of(s, now),
        "is_new": bool(s["created_at"] and now - s["created_at"] < timedelta(days=NEW_DAYS)),
        "owned": s["id"] in owned, "equipped": s["id"] in equipped,
    }


def col_out(c: dict, count: int, now: datetime) -> dict:
    return {"id": c["id"], "title": c["title"], "subtitle": c["subtitle"],
            "banner_url": c["banner_url"], "banner_kind": c["banner_kind"], "colors": c["colors"],
            "sale_until": _iso(c["sale_until"]), "status": status_of(c, now), "count": count}


def _owned(db: Session, user_id: str) -> set[str]:
    return {r[0] for r in db.query(UserItem.item_id).filter(UserItem.user_id == user_id).all()}


def _equipped(u: User) -> set[str]:
    return {x for x in (u.cover_item, u.avatar_frame, u.profile_fx) if x}


def _ctx(db: Session, me: User):
    rows = _rows(db)
    return rows, _owned(db, me.id), _equipped(me), _now()


def _visible(s: dict, owned: set[str], now: datetime) -> bool:
    return status_of(s, now) == "on_sale" or s["id"] in owned


def _search(rows: dict, q: str, owned: set[str], now: datetime, kind: str = "",
            collection: str = "", filt: str = "", rarity: str = "", sort: str = "popular",
            me: User | None = None) -> list[dict]:
    q = (q or "").strip().lower()
    words = [w for w in re.split(r"\s+", q) if w]
    out = []
    for iid in rows["order"]:
        s = rows["items"][iid]
        if filt == "owned":
            if iid not in owned:
                continue
        elif status_of(s, now) != "on_sale":
            continue
        if kind and s["kind"] != kind:
            continue
        if collection and s["collection"] != collection:
            continue
        if rarity and s["rarity"] != rarity:
            continue
        if filt == "free" and final_price(s, now) != 0:
            continue
        if filt == "sale" and discount_now(s, now) == 0:
            continue
        if filt == "premium" and not (s["premium_free"] or s["premium_only"]):
            continue
        if filt == "limited" and not (s["supply"] or s["sale_until"]):
            continue
        if filt == "new" and not (s["created_at"] and now - s["created_at"] < timedelta(days=NEW_DAYS)):
            continue
        if words:
            col = rows["cols"].get(s["collection"] or "")
            hay = " ".join([s["title"], s["description"], s["tags"], KIND_TITLES.get(s["kind"], ""),
                            col["title"] if col else "", s["rarity"]]).lower()
            if not all(w in hay for w in words):
                continue
        out.append(s)
    sold = rows["sold"]
    if sort == "new":
        out.sort(key=lambda s: s["created_at"] or now, reverse=True)
    elif sort == "price_asc":
        out.sort(key=lambda s: final_price(s, now))
    elif sort == "price_desc":
        out.sort(key=lambda s: -final_price(s, now))
    elif sort == "discount":
        out.sort(key=lambda s: -discount_now(s, now))
    else:
        out.sort(key=lambda s: (-int(sold.get(s["id"], 0)), s["sort"]))
    return out


# ── витрина ──

@router.get("/shop")
def shop_home(db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    rows, owned, equipped, now = _ctx(db, me)
    sold, cols = rows["sold"], rows["cols"]

    def out(lst, n=12):
        return [item_out(s, me, owned, equipped, sold, cols, now) for s in lst[:n]]

    on_sale = [rows["items"][i] for i in rows["order"] if status_of(rows["items"][i], now) == "on_sale"]
    counts = {}
    for s in on_sale:
        counts[s["kind"]] = counts.get(s["kind"], 0) + 1
        if s["collection"]:
            counts["col:" + s["collection"]] = counts.get("col:" + s["collection"], 0) + 1
    collections = [col_out(cols[c], counts.get("col:" + c, 0), now) for c in rows["col_order"]
                   if status_of(cols[c], now) == "on_sale" and counts.get("col:" + c)]
    featured_items = [s for s in on_sale if s["featured"]]
    newest = sorted(on_sale, key=lambda s: s["created_at"] or now, reverse=True)
    newest = [s for s in newest if s["created_at"] and now - s["created_at"] < timedelta(days=NEW_DAYS)]
    sale = sorted([s for s in on_sale if discount_now(s, now)], key=lambda s: -discount_now(s, now))
    free = [s for s in on_sale if final_price(s, now) == 0]
    popular = sorted(on_sale, key=lambda s: -int(sold.get(s["id"], 0)))
    limited = sorted([s for s in on_sale if s["supply"] or s["sale_until"]],
                     key=lambda s: s["sale_until"] or (now + timedelta(days=3650)))
    return {
        "balance": int(me.coins or 0),
        "is_premium": is_premium(me),
        "banners": [c for c in collections if cols[c["id"]]["featured"]],
        "collections": collections,
        "kinds": [{"id": k, "title": KIND_TITLES[k], "count": counts.get(k, 0)} for k in KINDS],
        "featured": out(featured_items, 8),
        "new": out(newest),
        "sale": out(sale),
        "free": out(free),
        "popular": out(popular),
        "limited": out(limited),
        "owned_count": len(owned),
        "total": len(on_sale),
    }


@router.get("/shop/items")
def shop_items(q: str = "", kind: str = "", collection: str = "", filter: str = "",
               rarity: str = "", sort: str = "popular", offset: int = 0, limit: int = 60,
               db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    if sort not in SORTS:
        sort = "popular"
    if filter and filter not in FILTERS:
        filter = ""
    rows, owned, equipped, now = _ctx(db, me)
    found = _search(rows, q, owned, now, kind, collection, filter, rarity, sort, me)
    limit = max(1, min(limit, 200))
    page = found[max(0, offset):max(0, offset) + limit]
    col = rows["cols"].get(collection) if collection else None
    return {"items": [item_out(s, me, owned, equipped, rows["sold"], rows["cols"], now) for s in page],
            "total": len(found), "balance": int(me.coins or 0),
            "collection": col_out(col, len(found), now) if col else None}


@router.get("/shop/items/{item_id}")
def shop_item(item_id: str, db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    rows, owned, equipped, now = _ctx(db, me)
    s = rows["items"].get(item_id)
    if s is None or not _visible(s, owned, now):
        raise HTTPException(status_code=404, detail="Товар не найден")
    d = item_out(s, me, owned, equipped, rows["sold"], rows["cols"], now)
    # похожие: та же коллекция или тот же тип
    similar = [x for x in _search(rows, "", owned, now, kind=s["kind"]) if x["id"] != item_id]
    same_col = [x for x in similar if s["collection"] and x["collection"] == s["collection"]]
    rest = [x for x in similar if x not in same_col]
    d["similar"] = [item_out(x, me, owned, equipped, rows["sold"], rows["cols"], now)
                    for x in (same_col + rest)[:10]]
    d["balance"] = int(me.coins or 0)
    return d


@router.get("/shop/inventory")
def shop_inventory(db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    rows, owned, equipped, now = _ctx(db, me)
    recs = (db.query(UserItem).filter(UserItem.user_id == me.id)
            .order_by(UserItem.created_at.desc()).all())
    items = []
    for r in recs:
        s = rows["items"].get(r.item_id)
        if s is None:
            continue
        d = item_out(s, me, owned, equipped, rows["sold"], rows["cols"], now)
        d["source"] = r.source
        d["acquired_at"] = _iso(as_utc(r.created_at))
        items.append(d)
    return {"items": items, "balance": int(me.coins or 0),
            "equipped": {"cover": me.cover_item, "frame": me.avatar_frame, "effect": me.profile_fx}}


class BuyIn(BaseModel):
    to_user_id: str | None = None
    text: str = Field(default="", max_length=200)


def _grant(db: Session, user: User, s: dict, source: str, price: int, from_id: str | None) -> None:
    db.add(UserItem(user_id=user.id, item_id=s["id"], source=source, price=price, from_id=from_id))


@router.post("/shop/items/{item_id}/buy")
def buy_item(item_id: str, data: BuyIn | None = None, db: Session = Depends(get_db),
             me: User = Depends(get_current_user)):
    from app.routers.economy import spend, _ws_me
    data = data or BuyIn()
    rows, owned, equipped, now = _ctx(db, me)
    s = rows["items"].get(item_id)
    if s is None:
        raise HTTPException(status_code=404, detail="Товар не найден")
    st = status_of(s, now)
    if st == "soon":
        raise HTTPException(status_code=410, detail="Этот товар ещё не в продаже")
    if st != "on_sale":
        raise HTTPException(status_code=410, detail="Этот товар больше не продаётся")
    if s["supply"]:
        sold = db.query(UserItem).filter(UserItem.item_id == item_id).count()
        if sold >= int(s["supply"]):
            raise HTTPException(status_code=410, detail="Лимитированный товар закончился")
    gift_to = None
    if data.to_user_id and data.to_user_id != me.id:
        gift_to = db.query(User).filter(User.id == data.to_user_id).first()
        if gift_to is None or gift_to.is_bot or gift_to.banned:
            raise HTTPException(status_code=404, detail="Пользователь не найден")
        if is_blocked(db, gift_to.id, me.id) or is_blocked(db, me.id, gift_to.id):
            raise HTTPException(status_code=403, detail="Нельзя подарить этому пользователю")
        if final_price(s, now) == 0:
            raise HTTPException(status_code=400, detail="Бесплатный товар можно просто забрать себе")
        if s["premium_only"] and not is_premium(gift_to):
            raise HTTPException(status_code=403, detail="Этот товар только для Premium")
        if db.query(UserItem).filter(UserItem.user_id == gift_to.id,
                                     UserItem.item_id == item_id).first():
            raise HTTPException(status_code=409, detail="У пользователя уже есть этот товар")
        price = final_price(s, now)
        name = gift_to.display_name or gift_to.username
        spend(db, me, price, "shop", f"«{s['title']}» в подарок для {name}")
        _grant(db, gift_to, s, "gift", price, me.id)
        db.commit()
        invalidate()
        _ws_me([me.id, gift_to.id])
        try:
            from app import sysbot
            who = me.display_name or me.username
            note = f"\n«{data.text.strip()}»" if data.text.strip() else ""
            sysbot.post(db, gift_to, f"🎁 {who} подарил(а) вам «{s['title']}» из магазина "
                                     f"оформления. Найти можно в Магазин → Мои предметы.{note}")
        except Exception:
            pass
        return {"ok": True, "gift": True, "balance": int(me.coins or 0)}
    if item_id in owned:
        raise HTTPException(status_code=409, detail="Этот товар уже у тебя")
    if s["premium_only"] and not is_premium(me):
        raise HTTPException(status_code=403, detail="Этот товар доступен только с Premium")
    price = price_for(s, me, now)
    if price > 0:
        spend(db, me, price, "shop", f"Магазин: «{s['title']}»")
    _grant(db, me, s, "buy" if price > 0 else "free", price, None)
    db.commit()
    invalidate()
    _ws_me([me.id])
    rows, owned, equipped, now = _ctx(db, me)
    return {"ok": True, "gift": False, "balance": int(me.coins or 0),
            "item": item_out(s, me, owned, equipped, rows["sold"], rows["cols"], now)}


def _slot(kind: str) -> str | None:
    return {"cover": "cover_item", "frame": "avatar_frame", "effect": "profile_fx"}.get(kind)


@router.post("/shop/items/{item_id}/equip")
def equip_item(item_id: str, db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    from app.routers.economy import _ws_me
    from app.users_out import me_dict
    s = item_snapshot(db, item_id)
    if s is None:
        raise HTTPException(status_code=404, detail="Товар не найден")
    if not db.query(UserItem).filter(UserItem.user_id == me.id, UserItem.item_id == item_id).first():
        raise HTTPException(status_code=403, detail="Сначала купи этот товар")
    slot = _slot(s["kind"])
    if slot is not None:
        setattr(me, slot, item_id)
        if s["kind"] == "cover":
            me.cover_url = s["media_url"]
            me.cover_kind = s["media_kind"]
        db.commit()
        _ws_me([me.id])
    # обои ставятся на устройстве — сервер только подтверждает владение
    return {"ok": True, "kind": s["kind"], "media_url": s["media_url"],
            "media_kind": s["media_kind"], "me": me_dict(db, me)}


class UnequipIn(BaseModel):
    kind: str


@router.post("/shop/unequip")
def unequip(data: UnequipIn, db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    from app.routers.economy import _ws_me
    from app.users_out import me_dict
    slot = _slot(data.kind)
    if slot is None:
        raise HTTPException(status_code=400, detail="Неизвестный тип")
    setattr(me, slot, None)
    if data.kind == "cover":
        me.cover_url = None
        me.cover_kind = None
    db.commit()
    _ws_me([me.id])
    return {"ok": True, "me": me_dict(db, me)}


# ── админка ──

class ItemIn(BaseModel):
    id: str | None = None
    kind: str
    title: str = Field(min_length=1, max_length=64)
    description: str = Field(default="", max_length=300)
    price: int = Field(default=0, ge=0, le=1_000_000)
    discount: int = Field(default=0, ge=0, le=95)
    discount_until: datetime | None = None
    premium_free: bool = False
    premium_only: bool = False
    rarity: str = "common"
    collection: str | None = None
    tags: str = Field(default="", max_length=256)
    media_url: str | None = None
    media_kind: str = "image"
    preview_url: str | None = None
    colors: list[str] | None = None
    supply: int | None = Field(default=None, ge=1, le=10_000_000)
    sale_from: datetime | None = None
    sale_until: datetime | None = None
    active: bool = True
    featured: bool = False
    sort: int = 0


class CollectionIn(BaseModel):
    id: str | None = None
    title: str = Field(min_length=1, max_length=64)
    subtitle: str = Field(default="", max_length=160)
    banner_url: str | None = None
    banner_kind: str = "image"
    colors: list[str] | None = None
    sale_from: datetime | None = None
    sale_until: datetime | None = None
    active: bool = True
    featured: bool = True
    sort: int = 0


_HEX = re.compile(r"#[0-9A-Fa-f]{6}")


def _clean_colors(c: list[str] | None) -> str | None:
    ok = [x for x in (c or []) if isinstance(x, str) and _HEX.fullmatch(x)][:3]
    return ",".join(ok) or None


def _utc(d: datetime | None) -> datetime | None:
    if d is None:
        return None
    return d.replace(tzinfo=timezone.utc) if d.tzinfo is None else d.astimezone(timezone.utc)


def _new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:8]}"


def _check_item(d: ItemIn) -> None:
    if d.kind not in KINDS:
        raise HTTPException(status_code=400, detail="Тип: cover, frame, effect или wallpaper")
    if d.rarity not in RARITIES:
        raise HTTPException(status_code=400, detail="Редкость: common, rare, epic, legendary")
    if d.media_kind not in MEDIA_KINDS:
        raise HTTPException(status_code=400, detail="Медиа: image или video")
    if d.id is not None and not _ID.fullmatch(d.id):
        raise HTTPException(status_code=400, detail="id: латиница, цифры и _, 2–48 символов")
    if d.sale_from and d.sale_until and _utc(d.sale_until) <= _utc(d.sale_from):
        raise HTTPException(status_code=400, detail="Конец продаж раньше начала")
    if d.kind == "frame" and d.media_kind != "image":
        raise HTTPException(status_code=400, detail="Рамка — картинка (png/webp с прозрачностью)")
    if d.kind == "effect" and d.media_kind != "image":
        raise HTTPException(status_code=400, detail="Анимация — анимированный webp/gif с прозрачностью")


def _apply_item(row: ShopItem, d: ItemIn) -> None:
    row.kind = d.kind
    row.title = d.title.strip()
    row.description = d.description.strip()
    row.price = d.price
    row.discount = d.discount
    row.discount_until = _utc(d.discount_until)
    row.premium_free = d.premium_free
    row.premium_only = d.premium_only
    row.rarity = d.rarity
    row.collection = (d.collection or "").strip() or None
    row.tags = d.tags.strip()
    row.media_url = (d.media_url or "").strip() or None
    row.media_kind = d.media_kind
    row.preview_url = (d.preview_url or "").strip() or None
    row.colors = _clean_colors(d.colors)
    row.supply = d.supply
    row.sale_from = _utc(d.sale_from)
    row.sale_until = _utc(d.sale_until)
    row.active = d.active
    row.featured = d.featured
    row.sort = d.sort


def _check_col(d: CollectionIn) -> None:
    if d.id is not None and not _ID.fullmatch(d.id):
        raise HTTPException(status_code=400, detail="id: латиница, цифры и _, 2–48 символов")
    if d.banner_kind not in MEDIA_KINDS:
        raise HTTPException(status_code=400, detail="Баннер: image или video")


def _apply_col(row: ShopCollection, d: CollectionIn) -> None:
    row.title = d.title.strip()
    row.subtitle = d.subtitle.strip()
    row.banner_url = (d.banner_url or "").strip() or None
    row.banner_kind = d.banner_kind
    row.colors = _clean_colors(d.colors)
    row.sale_from = _utc(d.sale_from)
    row.sale_until = _utc(d.sale_until)
    row.active = d.active
    row.featured = d.featured
    row.sort = d.sort


def _admin_item(db: Session, s: dict, now: datetime) -> dict:
    sold = _rows(db)["sold"]
    d = {k: (v.isoformat() if isinstance(v, datetime) else v) for k, v in s.items()}
    d["status"] = status_of(s, now)
    d["final_price"] = final_price(s, now)
    d["sold"] = int(sold.get(s["id"], 0))
    d["left"] = max(0, int(s["supply"]) - d["sold"]) if s["supply"] else None
    return d


def _admin_col(s: dict, count: int, now: datetime) -> dict:
    d = {k: (v.isoformat() if isinstance(v, datetime) else v) for k, v in s.items()}
    d["status"] = status_of(s, now)
    d["count"] = count
    return d


@admin_router.get("/items")
def admin_items(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    invalidate()
    rows, now = _rows(db), _now()
    return [_admin_item(db, rows["items"][i], now) for i in rows["order"]]


@admin_router.post("/items", status_code=201)
def admin_create_item(data: ItemIn, db: Session = Depends(get_db),
                      admin: User = Depends(require_admin)):
    _check_item(data)
    iid = data.id or _new_id(data.kind[:2])
    if db.get(ShopItem, iid) is not None:
        raise HTTPException(status_code=409, detail="Товар с таким id уже есть")
    row = ShopItem(id=iid)
    _apply_item(row, data)
    db.add(row)
    db.commit()
    invalidate()
    return _admin_item(db, _rows(db)["items"][iid], _now())


@admin_router.put("/items/{item_id}")
def admin_update_item(item_id: str, data: ItemIn, db: Session = Depends(get_db),
                      admin: User = Depends(require_admin)):
    row = db.get(ShopItem, item_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Товар не найден")
    data.id = None
    _check_item(data)
    if data.supply is not None:
        sold = db.query(UserItem).filter(UserItem.item_id == item_id).count()
        if data.supply < sold:
            raise HTTPException(status_code=400, detail=f"Уже продано {sold} — тираж не может быть меньше")
    _apply_item(row, data)
    db.commit()
    invalidate()
    return _admin_item(db, _rows(db)["items"][item_id], _now())


@admin_router.delete("/items/{item_id}")
def admin_delete_item(item_id: str, db: Session = Depends(get_db),
                      admin: User = Depends(require_admin)):
    row = db.get(ShopItem, item_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Товар не найден")
    if db.query(UserItem).filter(UserItem.item_id == item_id).first():
        # у кого-то он уже есть — не удаляем, а снимаем с продажи
        row.active = False
        db.commit()
        invalidate()
        return {"ok": True, "hidden": True}
    db.delete(row)
    db.commit()
    invalidate()
    return {"ok": True, "hidden": False}


@admin_router.get("/collections")
def admin_collections(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    invalidate()
    rows, now = _rows(db), _now()
    counts = {}
    for s in rows["items"].values():
        if s["collection"]:
            counts[s["collection"]] = counts.get(s["collection"], 0) + 1
    return [_admin_col(rows["cols"][c], counts.get(c, 0), now) for c in rows["col_order"]]


@admin_router.post("/collections", status_code=201)
def admin_create_col(data: CollectionIn, db: Session = Depends(get_db),
                     admin: User = Depends(require_admin)):
    _check_col(data)
    cid = data.id or _new_id("col")
    if db.get(ShopCollection, cid) is not None:
        raise HTTPException(status_code=409, detail="Коллекция с таким id уже есть")
    row = ShopCollection(id=cid)
    _apply_col(row, data)
    db.add(row)
    db.commit()
    invalidate()
    return _admin_col(_rows(db)["cols"][cid], 0, _now())


@admin_router.put("/collections/{col_id}")
def admin_update_col(col_id: str, data: CollectionIn, db: Session = Depends(get_db),
                     admin: User = Depends(require_admin)):
    row = db.get(ShopCollection, col_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Коллекция не найдена")
    data.id = None
    _check_col(data)
    _apply_col(row, data)
    db.commit()
    invalidate()
    return _admin_col(_rows(db)["cols"][col_id], 0, _now())


@admin_router.delete("/collections/{col_id}")
def admin_delete_col(col_id: str, db: Session = Depends(get_db),
                     admin: User = Depends(require_admin)):
    row = db.get(ShopCollection, col_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Коллекция не найдена")
    db.delete(row)
    db.commit()
    invalidate()
    return {"ok": True}


def _media_kind(ext: str) -> str | None:
    if ext in IMAGE_EXT:
        return "image"
    if ext in VIDEO_EXT:
        return "video"
    return None


def _save_bytes(raw: bytes, ext: str) -> str:
    os.makedirs(SHOP_DIR, exist_ok=True)
    name = f"{uuid.uuid4().hex}{ext}"
    with open(os.path.join(SHOP_DIR, name), "wb") as f:
        f.write(raw)
    return f"/media/shop/{name}"


def _poster(video_url: str) -> str | None:
    """Кадр-превью для видео (если на сервере есть ffmpeg)."""
    ff = shutil.which("ffmpeg")
    if not ff:
        return None
    src = video_url.replace("/media/", "media/", 1)
    name = f"{uuid.uuid4().hex}.jpg"
    dst = os.path.join(SHOP_DIR, name)
    try:
        subprocess.run([ff, "-y", "-loglevel", "error", "-ss", "0.5", "-i", src, "-frames:v", "1",
                        "-vf", "scale='min(720,iw)':-2", "-q:v", "4", dst],
                       timeout=30, check=True)
        return f"/media/shop/{name}" if os.path.exists(dst) else None
    except Exception:
        return None


@admin_router.post("/media")
async def admin_media(file: UploadFile = File(...), admin: User = Depends(require_admin)):
    ext = os.path.splitext(file.filename or "")[1].lower()
    kind = _media_kind(ext)
    if kind is None:
        raise HTTPException(status_code=400, detail="Нужна картинка (png/jpg/webp/gif) или видео (mp4/webm)")
    raw = await file.read(MAX_MEDIA + 1)
    if len(raw) > MAX_MEDIA:
        raise HTTPException(status_code=413, detail="Файл больше 80 МБ")
    url = _save_bytes(raw, ext)
    return {"url": url, "kind": kind, "preview_url": _poster(url) if kind == "video" else url,
            "size": len(raw)}


def _parse_dt(v) -> datetime | None:
    if not v:
        return None
    try:
        return _utc(datetime.fromisoformat(str(v).replace("Z", "+00:00")))
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Неверная дата: {v}")


@admin_router.post("/import")
async def admin_import(file: UploadFile = File(...), db: Session = Depends(get_db),
                       admin: User = Depends(require_admin)):
    """Пак: zip с shop.json и файлами. Товары с тем же id обновляются (медиа — если приложено)."""
    raw = await file.read(MAX_PACK + 1)
    if len(raw) > MAX_PACK:
        raise HTTPException(status_code=413, detail="Архив больше 600 МБ")
    try:
        zf = zipfile.ZipFile(io.BytesIO(raw))
    except zipfile.BadZipFile:
        raise HTTPException(status_code=400, detail="Это не zip-архив")
    names = {os.path.basename(n): n for n in zf.namelist() if not n.endswith("/")}
    if "shop.json" not in names:
        raise HTTPException(status_code=400, detail="В архиве нет shop.json")
    try:
        spec = json.loads(zf.read(names["shop.json"]).decode("utf-8-sig"))
    except Exception:
        raise HTTPException(status_code=400, detail="shop.json не читается (проверь JSON)")
    saved: dict[str, str] = {}

    def media(fname: str | None) -> tuple[str | None, str | None]:
        if not fname:
            return None, None
        base = os.path.basename(str(fname))
        if base in saved:
            return saved[base], _media_kind(os.path.splitext(base)[1].lower())
        if base not in names:
            raise HTTPException(status_code=400, detail=f"В архиве нет файла {base}")
        ext = os.path.splitext(base)[1].lower()
        kind = _media_kind(ext)
        if kind is None:
            raise HTTPException(status_code=400, detail=f"Неподдерживаемый файл {base}")
        url = _save_bytes(zf.read(names[base]), ext)
        saved[base] = url
        return url, kind

    stats = {"collections": 0, "items": 0, "gifts": 0}
    for c in spec.get("collections") or []:
        cid = str(c.get("id") or "")
        if not _ID.fullmatch(cid):
            raise HTTPException(status_code=400, detail=f"Плохой id коллекции: {cid}")
        row = db.get(ShopCollection, cid) or ShopCollection(id=cid)
        url, kind = media(c.get("banner"))
        data = CollectionIn(
            title=c.get("title") or cid, subtitle=c.get("subtitle") or "",
            banner_url=url or c.get("banner_url") or row.banner_url,
            banner_kind=kind or c.get("banner_kind") or row.banner_kind or "image",
            colors=c.get("colors"), sale_from=_parse_dt(c.get("sale_from")),
            sale_until=_parse_dt(c.get("sale_until")), active=c.get("active", True),
            featured=c.get("featured", True), sort=int(c.get("sort") or 0))
        _check_col(data)
        _apply_col(row, data)
        db.merge(row)
        stats["collections"] += 1
    for n, it in enumerate(spec.get("items") or []):
        iid = str(it.get("id") or "")
        if not _ID.fullmatch(iid):
            raise HTTPException(status_code=400, detail=f"Плохой id товара: {iid}")
        row = db.get(ShopItem, iid)
        url, kind = media(it.get("media"))
        purl, _ = media(it.get("preview"))
        data = ItemIn(
            kind=it.get("kind", ""), title=it.get("title") or iid,
            description=it.get("description") or "", price=int(it.get("price") or 0),
            discount=int(it.get("discount") or 0), discount_until=_parse_dt(it.get("discount_until")),
            premium_free=bool(it.get("premium_free")), premium_only=bool(it.get("premium_only")),
            rarity=it.get("rarity") or "common", collection=it.get("collection"),
            tags=it.get("tags") or "",
            media_url=url or (row.media_url if row else None),
            media_kind=kind or it.get("media_kind") or (row.media_kind if row else "image"),
            preview_url=purl or (row.preview_url if row else None),
            colors=it.get("colors"), supply=it.get("supply"),
            sale_from=_parse_dt(it.get("sale_from")), sale_until=_parse_dt(it.get("sale_until")),
            active=it.get("active", True), featured=bool(it.get("featured")),
            sort=int(it.get("sort") if it.get("sort") is not None else n * 10))
        _check_item(data)
        if row is None:
            row = ShopItem(id=iid)
            db.add(row)
        _apply_item(row, data)
        stats["items"] += 1
    for n, g in enumerate(spec.get("gifts") or []):
        gid = str(g.get("id") or "")
        if not re.fullmatch(r"[a-z0-9_]{2,32}", gid):
            raise HTTPException(status_code=400, detail=f"Плохой id подарка: {gid}")
        if g.get("rarity", "common") not in RARITIES:
            raise HTTPException(status_code=400, detail=f"Плохая редкость у подарка {gid}")
        row = db.get(GiftDef, gid)
        url, _ = media(g.get("image"))
        if row is None:
            row = GiftDef(id=gid)
            db.add(row)
        row.title = (g.get("title") or gid)[:64]
        row.emoji = g.get("emoji") or row.emoji or "🎁"
        row.price = max(1, int(g.get("price") or 10))
        row.rarity = g.get("rarity") or "common"
        row.supply = g.get("supply")
        row.image_url = url or row.image_url
        row.colors = _clean_colors(g.get("colors"))
        row.sale_from = _parse_dt(g.get("sale_from"))
        row.sale_until = _parse_dt(g.get("sale_until"))
        row.active = g.get("active", True)
        row.sort = int(g.get("sort") if g.get("sort") is not None else 1000 + n * 10)
        for k in ("bg", "fx", "anim", "symbol"):
            if g.get(k) is not None:
                setattr(row, k, g.get(k) or None)
        stats["gifts"] += 1
    db.commit()
    invalidate()
    if stats["gifts"]:
        from app.routers.economy import invalidate_gifts
        invalidate_gifts()
    stats["files"] = len(saved)
    return stats
