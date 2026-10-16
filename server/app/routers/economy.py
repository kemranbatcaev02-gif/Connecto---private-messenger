"""Коины (внутренняя валюта), подарки и Premium за коины.

Курс: 100 коинов = 49 ₽, крупные пакеты — выгоднее.
Оплата — ЮKassa. Чтобы включить, положи рядом с сервером файл yookassa.json:
{
  "shop_id": "123456",
  "secret_key": "live_xxx",
  "return_url": "http://193.233.112.115:8000/pay/done"
}
и в личном кабинете ЮKassa укажи адрес уведомлений:
http://<сервер>/coins/yookassa/webhook  (событие payment.succeeded).
Пока файла нет — покупка за рубли выключена, коины можно получить
ежедневным бонусом, промокодом или от админа.
"""
import base64
import json
import os
import urllib.request
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.deps import get_current_user, get_db
from app.database import SessionLocal
from app.models.user import User
from app.models.chat import Chat, ChatMember, Message
from app.models.social import CoinTx, GiftDef, Payment, UserGift
from app.privacy import allowed, is_blocked, is_premium, as_utc
from app.users_out import me_dict

router = APIRouter(tags=["coins"])
gifts_router = APIRouter(tags=["gifts"])

YK_FILE = "yookassa.json"

# ── пакеты коинов: базовая цена 0,49 ₽ за коин, дальше скидка ──
BASE_RUB_PER_100 = 49
PACKAGES = [
    {"id": "c100", "coins": 100, "rub": 49},
    {"id": "c250", "coins": 250, "rub": 119},
    {"id": "c500", "coins": 500, "rub": 229},
    {"id": "c1000", "coins": 1000, "rub": 439},
    {"id": "c2500", "coins": 2500, "rub": 1049},
    {"id": "c5000", "coins": 5000, "rub": 1990},
]
for _p in PACKAGES:
    _full = _p["coins"] * BASE_RUB_PER_100 / 100
    _p["discount"] = max(0, round((1 - _p["rub"] / _full) * 100))
    _p["popular"] = _p["id"] == "c1000"

# ── Premium за коины ──
PREMIUM_PLANS = [
    {"id": "p1", "days": 30, "coins": 299, "title": "1 месяц"},
    {"id": "p3", "days": 90, "coins": 799, "title": "3 месяца"},
    {"id": "p12", "days": 365, "coins": 2499, "title": "12 месяцев"},
]
for _p in PREMIUM_PLANS:
    _full = _p["days"] / 30 * 299
    _p["discount"] = max(0, round((1 - _p["coins"] / _full) * 100))
    # цена в рублях при покупке напрямую (по курсу коинов) — поменяй, если хочешь другую
    _p["rub"] = round(_p["coins"] * BASE_RUB_PER_100 / 100)

# ── ежедневный бонус: серия из 7 дней, Premium — вдвое больше ──
DAILY = [1, 1, 2, 2, 3, 3, 5]

# ── подарки: common — простые, rare — градиент, epic — анимация, legendary — золото ──
# Это только стартовый набор: при первом запуске он попадает в таблицу gift_defs,
# а дальше подарки добавляются и меняются из админки (Админ-панель → Подарки).
RARITIES = ("common", "rare", "epic", "legendary")
# оформление подарков (рисует приложение; пусто/auto — классический вид по редкости)
GIFT_BGS = ("auto", "none", "soft", "glow", "gradient", "aurora", "rays", "starry", "gold",
            "neon", "holo", "pattern", "velvet", "sunset")
GIFT_FXS = ("auto", "none", "sparkles", "bubbles", "snow", "embers", "hearts", "stars",
            "confetti", "orbit", "shine", "fireflies", "float")
GIFT_ANIMS = ("auto", "none", "float", "bounce", "pulse", "swing", "wobble", "spin")
GIFTS = [
    {"id": "rose", "emoji": "🌹", "title": "Роза", "price": 15, "rarity": "common"},
    {"id": "chocolate", "emoji": "🍫", "title": "Шоколадка", "price": 20, "rarity": "common"},
    {"id": "coffee", "emoji": "☕", "title": "Кофе", "price": 25, "rarity": "common"},
    {"id": "balloon", "emoji": "🎈", "title": "Шарик", "price": 30, "rarity": "common"},
    {"id": "teddy", "emoji": "🧸", "title": "Мишка", "price": 40, "rarity": "common"},
    {"id": "bouquet", "emoji": "💐", "title": "Букет", "price": 60, "rarity": "rare"},
    {"id": "cake", "emoji": "🎂", "title": "Торт", "price": 80, "rarity": "rare"},
    {"id": "gamepad", "emoji": "🎮", "title": "Геймпад", "price": 100, "rarity": "rare"},
    {"id": "champagne", "emoji": "🍾", "title": "Шампанское", "price": 150, "rarity": "rare"},
    {"id": "ring", "emoji": "💍", "title": "Кольцо", "price": 250, "rarity": "epic"},
    {"id": "trophy", "emoji": "🏆", "title": "Кубок", "price": 350, "rarity": "epic"},
    {"id": "rocket", "emoji": "🚀", "title": "Ракета", "price": 500, "rarity": "epic"},
    {"id": "diamond", "emoji": "💎", "title": "Бриллиант", "price": 800, "rarity": "legendary",
     "supply": 500},
    {"id": "crown", "emoji": "👑", "title": "Корона", "price": 1200, "rarity": "legendary",
     "supply": 300},
    {"id": "dragon", "emoji": "🐉", "title": "Дракон", "price": 2500, "rarity": "legendary",
     "supply": 100},
]
CONVERT_RATE = 0.7   # подарок можно обменять на 70% его цены
MAX_PINNED_GIFTS = 6

# ── улучшение до уникального: случайный фон и узор (вес = шанс в тысячных) ──
BACKDROPS = [
    {"id": "midnight", "name": "Полночь", "colors": ["#3B5BDB", "#0B1026"], "w": 200},
    {"id": "emerald", "name": "Изумруд", "colors": ["#34D399", "#064E3B"], "w": 160},
    {"id": "ruby", "name": "Рубин", "colors": ["#FB7185", "#7F1D1D"], "w": 150},
    {"id": "amethyst", "name": "Аметист", "colors": ["#C084FC", "#3B0764"], "w": 150},
    {"id": "ocean", "name": "Океан", "colors": ["#38BDF8", "#0C4A6E"], "w": 120},
    {"id": "sunset", "name": "Закат", "colors": ["#FDBA74", "#9A3412"], "w": 100},
    {"id": "mint", "name": "Мята", "colors": ["#A7F3D0", "#047857"], "w": 50},
    {"id": "rose_gold", "name": "Розовое золото", "colors": ["#FFE4E6", "#B76E79"], "w": 40},
    {"id": "onyx", "name": "Чёрный оникс", "colors": ["#4B5563", "#030712"], "w": 20},
    {"id": "gold", "name": "Чистое золото", "colors": ["#FEF3C7", "#B45309"], "w": 10},
]
PATTERNS = [
    {"id": "stars", "name": "Звёзды", "symbol": "✦", "w": 220},
    {"id": "hearts", "name": "Сердца", "symbol": "♥", "w": 200},
    {"id": "sparkles", "name": "Искры", "symbol": "✧", "w": 180},
    {"id": "moons", "name": "Луны", "symbol": "☾", "w": 150},
    {"id": "clover", "name": "Клевер", "symbol": "☘", "w": 110},
    {"id": "diamonds", "name": "Ромбы", "symbol": "◆", "w": 80},
    {"id": "snow", "name": "Снежинки", "symbol": "❄", "w": 40},
    {"id": "crowns", "name": "Короны", "symbol": "♛", "w": 20},
]
BACKDROP_BY_ID = {b["id"]: b for b in BACKDROPS}
PATTERN_BY_ID = {p["id"]: p for p in PATTERNS}
_BW = sum(b["w"] for b in BACKDROPS)
_PW = sum(p["w"] for p in PATTERNS)


# ── каталог подарков из базы (с коротким кэшем: подарки читаются очень часто) ──
_GIFT_CACHE: dict | None = None
_GIFT_CACHE_AT = 0.0
_GIFT_TTL = 20.0


def seed_gifts(db: Session) -> None:
    """Первый запуск: переносим встроенные подарки в базу (дальше — только админка)."""
    have = {r[0] for r in db.query(GiftDef.id).all()}
    added = False
    for i, g in enumerate(GIFTS):
        if g["id"] in have:
            continue
        db.add(GiftDef(id=g["id"], title=g["title"], emoji=g["emoji"], price=g["price"],
                       rarity=g["rarity"], supply=g.get("supply"), sort=i * 10))
        added = True
    if added:
        db.commit()
    invalidate_gifts()


def invalidate_gifts() -> None:
    global _GIFT_CACHE
    _GIFT_CACHE = None


def def_dict(g: GiftDef) -> dict:
    """Подарок так, как его видит приложение."""
    d = {"id": g.id, "emoji": g.emoji or "🎁", "title": g.title, "price": int(g.price),
         "rarity": g.rarity if g.rarity in RARITIES else "common"}
    if g.supply:
        d["supply"] = int(g.supply)
    if g.image_url:
        d["image_url"] = g.image_url
    if g.colors:
        d["colors"] = [c for c in g.colors.split(",") if c][:3]
    if g.sale_from:
        d["sale_from"] = as_utc(g.sale_from).isoformat()
    if g.sale_until:
        d["sale_until"] = as_utc(g.sale_until).isoformat()
    for k in ("bg", "fx", "anim", "symbol"):
        v = getattr(g, k, None)
        if v:
            d[k] = v
    return d


def _gift_rows(db: Session) -> dict:
    """id → (строка из базы, словарь для приложения)."""
    import time
    global _GIFT_CACHE, _GIFT_CACHE_AT
    now = time.monotonic()
    if _GIFT_CACHE is None or now - _GIFT_CACHE_AT > _GIFT_TTL:
        rows = db.query(GiftDef).order_by(GiftDef.sort.asc(), GiftDef.price.asc()).all()
        _GIFT_CACHE = {r.id: {"active": bool(r.active),
                              "sale_from": as_utc(r.sale_from), "sale_until": as_utc(r.sale_until),
                              "sort": r.sort, "d": def_dict(r)} for r in rows}
        _GIFT_CACHE_AT = now
    return _GIFT_CACHE


def get_gift(db: Session, gift_id: str) -> dict | None:
    row = _gift_rows(db).get(gift_id)
    return dict(row["d"]) if row else None


def gift_status(row: dict, now: datetime | None = None) -> str:
    """on_sale — продаётся, soon — ещё не начался, ended — закончился срок, off — выключен."""
    now = now or datetime.now(timezone.utc)
    if not row["active"]:
        return "off"
    if row["sale_from"] and now < row["sale_from"]:
        return "soon"
    if row["sale_until"] and now >= row["sale_until"]:
        return "ended"
    return "on_sale"


def all_gifts(db: Session) -> list[tuple[dict, str]]:
    """Все подарки (для админки): (словарь, статус)."""
    now = datetime.now(timezone.utc)
    return [(dict(r["d"]), gift_status(r, now)) for r in _gift_rows(db).values()]


def upgrade_cost(price: int) -> int:
    return max(25, int(price * 0.5))


def _pct(w: int, total: int) -> float:
    return round(w * 100 / total, 1)


def unique_info(ug: UserGift) -> dict | None:
    if not ug.upgraded:
        return None
    b = BACKDROP_BY_ID.get(ug.backdrop or "") or BACKDROPS[0]
    p = PATTERN_BY_ID.get(ug.pattern or "") or PATTERNS[0]
    bp, pp = _pct(b["w"], _BW), _pct(p["w"], _PW)
    base = int(ug.price or 0) + int(ug.upgrade_cost or 0)
    # чем реже фон и узор, тем дороже оценка
    mult = (1 + 2 / max(bp, 0.5)) * (1 + 2 / max(pp, 0.5))
    return {
        "no": ug.unique_no,
        "backdrop": {"id": b["id"], "name": b["name"], "colors": b["colors"], "pct": bp},
        "pattern": {"id": p["id"], "name": p["name"], "symbol": p["symbol"], "pct": pp},
        "value": int(base * mult),
    }


def _now():
    return datetime.now(timezone.utc)


def _today() -> str:
    return _now().strftime("%Y-%m-%d")


def _mini(u: User | None) -> dict | None:
    if u is None:
        return None
    return {"id": u.id, "display_name": u.display_name or u.username,
            "avatar_url": u.avatar_url, "is_premium": is_premium(u),
            "is_verified": bool(u.is_verified)}


def add_coins(db: Session, user: User, amount: int, kind: str, title: str) -> None:
    """Изменить баланс и записать в историю (без commit)."""
    user.coins = int(user.coins or 0) + int(amount)
    db.add(CoinTx(user_id=user.id, amount=int(amount), kind=kind, title=title[:128]))


def spend(db: Session, user: User, amount: int, kind: str, title: str) -> None:
    if int(user.coins or 0) < amount:
        raise HTTPException(status_code=402,
                            detail=f"Не хватает коинов: нужно {amount}, у тебя {int(user.coins or 0)}")
    add_coins(db, user, -amount, kind, title)


def _ws_me(user_ids: list[str]) -> None:
    from app.messaging import send_ws_sync
    send_ws_sync(user_ids, {"type": "me_updated"})


# ── ЮKassa ──

def yk_cfg() -> dict | None:
    try:
        if os.path.exists(YK_FILE):
            with open(YK_FILE, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            if cfg.get("shop_id") and cfg.get("secret_key"):
                return cfg
    except Exception:
        pass
    return None


def _yk_request(method: str, path: str, body: dict | None = None,
                idem: str | None = None) -> dict:
    cfg = yk_cfg()
    if cfg is None:
        raise HTTPException(status_code=503, detail="Оплата не настроена")
    auth = base64.b64encode(f"{cfg['shop_id']}:{cfg['secret_key']}".encode()).decode()
    headers = {"Authorization": f"Basic {auth}", "Content-Type": "application/json"}
    if idem:
        headers["Idempotence-Key"] = idem
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"https://api.yookassa.ru/v3{path}", data=data,
                                 method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read().decode())
    except Exception:
        raise HTTPException(status_code=502, detail="Платёжный сервис не ответил, попробуй позже")


def _credit(db: Session, pay: Payment) -> bool:
    """Зачислить коины за оплаченный платёж (ровно один раз)."""
    if pay.status == "succeeded":
        return False
    user = db.query(User).filter(User.id == pay.user_id).first()
    if user is None:
        return False
    # атомарно «забираем» платёж: вебхук и проверка из приложения могут прийти одновременно
    won = (db.query(Payment).filter(Payment.id == pay.id, Payment.status == "pending")
           .update({"status": "succeeded"}, synchronize_session=False))
    if won != 1:
        db.rollback()
        return False
    pay.status = "succeeded"
    add_coins(db, user, pay.coins, "purchase", f"Покупка {pay.coins} коинов")
    db.commit()
    _ws_me([user.id])
    return True


def _sync_payment(db: Session, pay: Payment) -> Payment:
    if pay.status != "pending" or not pay.provider_id:
        return pay
    if pay.provider_id.startswith("rp:"):
        # платёж RollyPay (когда включишь — раскомментируй):
        # from app.routers import rollypay
        # return rollypay.sync_payment(db, pay)
        return pay
    if yk_cfg() is None:
        return pay
    obj = _yk_request("GET", f"/payments/{pay.provider_id}")
    st = obj.get("status")
    if st == "succeeded" and (obj.get("metadata") or {}).get("payment_id") == pay.id:
        _credit(db, pay)
    elif st == "canceled":
        pay.status = "canceled"
        db.commit()
    return pay


def _pay_dict(p: Payment) -> dict:
    return {"id": p.id, "status": p.status, "coins": p.coins, "rub": p.rub,
            "confirmation_url": p.confirmation_url,
            "created_at": as_utc(p.created_at).isoformat() if p.created_at else None}


# ── кошелёк ──

def _daily_state(user: User) -> dict:
    today = _today()
    yesterday = (_now() - timedelta(days=1)).strftime("%Y-%m-%d")
    streak = int(user.daily_streak or 0)
    claimed = user.daily_last == today
    nxt = streak + 1 if user.daily_last == yesterday else 1
    if claimed:
        nxt = streak + 1
    mult = 2 if is_premium(user) else 1
    day = (nxt - 1) % len(DAILY)
    return {"available": not claimed, "streak": streak if (claimed or user.daily_last == yesterday) else 0,
            "next_day": day + 1, "reward": DAILY[day] * mult, "premium_x2": mult == 2,
            "rewards": [r * mult for r in DAILY]}


def seller_info(db: Session) -> dict:
    """Кому писать, чтобы купить коины/Premium (пока нет онлайн-оплаты)."""
    from app.config import SELLER_EMAIL, SELLER_TELEGRAM
    u = db.query(User).filter(User.email == SELLER_EMAIL.lower()).first()
    return {
        "user_id": u.id if u is not None and not u.banned else None,
        "name": (u.display_name or u.username) if u is not None else None,
        "handle": u.handle if u is not None else None,
        "avatar_url": u.avatar_url if u is not None else None,
        "telegram": SELLER_TELEGRAM,
    }


@router.get("/coins")
def wallet(db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    return {
        "balance": int(me.coins or 0),
        "packages": PACKAGES,
        "premium_plans": PREMIUM_PLANS,
        "daily": _daily_state(me),
        "payments_enabled": yk_cfg() is not None,
        "rate": "100 коинов = 49 ₽",
        "seller": seller_info(db),
    }


@router.get("/coins/shop")
def shop(db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    """Витрина для покупки через продавца: пакеты, тарифы Premium и контакты."""
    return {"packages": PACKAGES, "premium_plans": PREMIUM_PLANS,
            "payments_enabled": yk_cfg() is not None, "seller": seller_info(db)}


@router.get("/coins/history")
def history(db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    rows = (db.query(CoinTx).filter(CoinTx.user_id == me.id)
            .order_by(CoinTx.created_at.desc()).limit(100).all())
    return [{"id": r.id, "amount": r.amount, "kind": r.kind, "title": r.title,
             "created_at": as_utc(r.created_at).isoformat() if r.created_at else None}
            for r in rows]


@router.post("/coins/daily")
def claim_daily(db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    st = _daily_state(me)
    if not st["available"]:
        raise HTTPException(status_code=400, detail="Бонус уже получен, приходи завтра")
    yesterday = (_now() - timedelta(days=1)).strftime("%Y-%m-%d")
    me.daily_streak = (int(me.daily_streak or 0) + 1) if me.daily_last == yesterday else 1
    me.daily_last = _today()
    add_coins(db, me, st["reward"], "daily", f"Ежедневный бонус · день {st['next_day']}")
    db.commit()
    return {"reward": st["reward"], "balance": int(me.coins or 0), "daily": _daily_state(me)}


class BuyIn(BaseModel):
    package_id: str


@router.post("/coins/buy")
def buy_coins(data: BuyIn, db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    pkg = next((p for p in PACKAGES if p["id"] == data.package_id), None)
    if pkg is None:
        raise HTTPException(status_code=404, detail="Пакет не найден")
    # ── RollyPay (СБП, карты, крипта) — код готов в app/routers/rollypay.py ──
    # Когда подключишь кассу, раскомментируй 3 строки ниже (и строку в main.py):
    # from app.routers import rollypay
    # if rollypay.rp_cfg() is not None:
    #     return rollypay.create_coins_payment(db, me, pkg)
    cfg = yk_cfg()
    if cfg is None:
        raise HTTPException(status_code=503,
                            detail="Оплата картой скоро появится. Пока коины можно получить "
                                   "ежедневным бонусом или промокодом")
    pay = Payment(user_id=me.id, package_id=pkg["id"], coins=pkg["coins"], rub=pkg["rub"])
    db.add(pay)
    db.commit()
    db.refresh(pay)
    obj = _yk_request("POST", "/payments", {
        "amount": {"value": f"{pkg['rub']}.00", "currency": "RUB"},
        "capture": True,
        "confirmation": {"type": "redirect",
                         "return_url": cfg.get("return_url") or "https://yookassa.ru"},
        "description": f"Connecto: {pkg['coins']} коинов",
        "metadata": {"payment_id": pay.id, "user_id": me.id},
    }, idem=pay.id)
    pay.provider_id = obj.get("id")
    pay.confirmation_url = (obj.get("confirmation") or {}).get("confirmation_url")
    db.commit()
    return _pay_dict(pay)


@router.get("/coins/payments/{payment_id}")
def payment_status(payment_id: str, db: Session = Depends(get_db),
                   me: User = Depends(get_current_user)):
    pay = db.query(Payment).filter(Payment.id == payment_id, Payment.user_id == me.id).first()
    if pay is None:
        raise HTTPException(status_code=404, detail="Платёж не найден")
    _sync_payment(db, pay)
    out = _pay_dict(pay)
    out["balance"] = int(me.coins or 0)
    return out


@router.post("/coins/yookassa/webhook")
async def yk_webhook(request: Request):
    """Уведомление ЮKassa. Не верим телу на слово — перепроверяем платёж через API."""
    try:
        body = await request.json()
    except Exception:
        return {"ok": True}
    obj = body.get("object") or {}
    pid = obj.get("id")
    our = (obj.get("metadata") or {}).get("payment_id")
    if not pid or not our:
        return {"ok": True}
    from fastapi.concurrency import run_in_threadpool

    def work():
        db = SessionLocal()
        try:
            pay = db.query(Payment).filter(Payment.id == our, Payment.provider_id == pid).first()
            if pay is not None:
                _sync_payment(db, pay)
        finally:
            db.close()
    try:
        await run_in_threadpool(work)
    except Exception:
        pass
    return {"ok": True}


@router.get("/pay/done", response_class=HTMLResponse)
def pay_done():
    return """<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Connecto</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0a0b0f;
color:#f5f6f8;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
.c{max-width:340px;margin:24px;padding:32px 26px;border-radius:26px;background:#15171e;text-align:center}
.l{font-size:56px}h1{font-size:22px;margin:10px 0 6px}p{color:#8a8f9c;line-height:1.45}</style>
</head><body><div class="c"><div class="l">🪙</div><h1>Спасибо!</h1>
<p>Когда оплата пройдёт, коины появятся на балансе. Можно вернуться в Connecto.</p>
</div></body></html>"""


# ── Premium за коины (себе или в подарок) ──

class PremiumBuyIn(BaseModel):
    plan_id: str
    to_user_id: str | None = None


@router.post("/coins/premium")
def buy_premium(data: PremiumBuyIn, db: Session = Depends(get_db),
                me: User = Depends(get_current_user)):
    from app.routers.premium import grant
    from app import sysbot
    plan = next((p for p in PREMIUM_PLANS if p["id"] == data.plan_id), None)
    if plan is None:
        raise HTTPException(status_code=404, detail="Тариф не найден")
    target = me
    if data.to_user_id and data.to_user_id != me.id:
        target = db.query(User).filter(User.id == data.to_user_id).first()
        if target is None or target.is_bot:
            raise HTTPException(status_code=404, detail="Пользователь не найден")
        if is_blocked(db, target.id, me.id):
            raise HTTPException(status_code=403, detail="Пользователь ограничил подарки от вас")
    who = "себе" if target.id == me.id else f"для {target.display_name or target.username}"
    spend(db, me, plan["coins"], "premium", f"Premium на {plan['title']} {who}")
    grant(target, plan["days"])
    db.commit()
    _ws_me([me.id, target.id])
    if target.id != me.id:
        try:
            sysbot.post(db, target, f"⭐ {me.display_name or me.username} подарил(а) вам "
                                    f"Connecto Premium на {plan['title']}!")
        except Exception:
            pass
    return me_dict(db, me)


# ── подарки ──

def _sold(db: Session, gift_id: str) -> int:
    return db.query(UserGift).filter(UserGift.gift_id == gift_id).count()


def catalog(db: Session) -> list[dict]:
    out = []
    for g, st in all_gifts(db):
        if st != "on_sale":
            continue
        d = dict(g)
        d["convert_value"] = int(g["price"] * CONVERT_RATE)
        if g.get("supply"):
            d["sold"] = _sold(db, g["id"])
            d["left"] = max(0, g["supply"] - d["sold"])
        out.append(d)
    return out


def _direct_chat(db: Session, a_id: str, b_id: str) -> Chat:
    mine = db.query(ChatMember.chat_id).filter(ChatMember.user_id == a_id)
    row = (db.query(Chat).join(ChatMember, ChatMember.chat_id == Chat.id)
           .filter(Chat.type == "direct", Chat.is_system == False,  # noqa: E712
                   ChatMember.user_id == b_id, Chat.id.in_(mine)).first())
    if row is not None:
        return row
    chat = Chat(type="direct")
    db.add(chat)
    db.flush()
    db.add(ChatMember(chat_id=chat.id, user_id=a_id, role="member"))
    db.add(ChatMember(chat_id=chat.id, user_id=b_id, role="member"))
    db.commit()
    db.refresh(chat)
    return chat


def gift_dict(db: Session, ug: UserGift, viewer_id: str, users: dict | None = None) -> dict:
    g = get_gift(db, ug.gift_id) or {"id": ug.gift_id, "emoji": "🎁", "title": "Подарок",
                                     "price": ug.price, "rarity": "common"}
    mine = ug.to_id == viewer_id
    sender = None
    if ug.from_id and (not ug.anonymous or mine or ug.from_id == viewer_id):
        u = (users or {}).get(ug.from_id) or db.query(User).filter(User.id == ug.from_id).first()
        sender = _mini(u)
    uniq = unique_info(ug)
    price = int(ug.price or g["price"])
    return {
        "id": ug.id,
        "gift": g,
        "from": sender,
        "unique": uniq,
        "pinned": bool(ug.pinned),
        "value": uniq["value"] if uniq else price,
        "upgrade_cost": None if ug.upgraded else upgrade_cost(price),
        "anonymous": bool(ug.anonymous),
        "text": ug.text or "",
        "serial": ug.serial,
        "supply": g.get("supply"),
        "hidden": bool(ug.hidden),
        "converted": bool(ug.converted),
        "convert_value": 0 if ug.upgraded else int(price * CONVERT_RATE),
        "mine": mine,
        "created_at": as_utc(ug.created_at).isoformat() if ug.created_at else None,
    }


@gifts_router.get("/gifts/catalog")
def gifts_catalog(db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    return {"gifts": catalog(db), "balance": int(me.coins or 0)}


class GiftSendIn(BaseModel):
    to_user_id: str
    gift_id: str
    text: str = Field(default="", max_length=200)
    anonymous: bool = False


async def create_gift(db: Session, g: dict, to: User, giver: User | None, text: str,
                      anonymous: bool) -> UserGift:
    """Создать подарок и доставить его сообщением. giver=None — подарок от Connecto."""
    from app.messaging import deliver
    from app import sysbot
    serial = None
    if g.get("supply"):
        sold = _sold(db, g["id"])
        if sold >= g["supply"]:
            raise HTTPException(status_code=410, detail="Этот лимитированный подарок закончился")
        serial = sold + 1
    ug = UserGift(gift_id=g["id"], from_id=giver.id if giver else None, to_id=to.id,
                  text=text.strip(), anonymous=anonymous, serial=serial, price=g["price"])
    db.add(ug)
    db.commit()
    db.refresh(ug)
    info = gift_dict(db, ug, to.id)
    extra = json.dumps({"gift": {"user_gift_id": ug.id, "gift": g, "serial": serial,
                                 "anonymous": bool(anonymous),
                                 "convert_value": info["convert_value"],
                                 "from_connecto": giver is None}},
                       ensure_ascii=False)
    if giver is None or to.id != giver.id:
        if anonymous or giver is None:
            # анонимно или от Connecto — через бота, чтобы не раскрыть отправителя
            bot = sysbot.get_bot(db)
            chat = sysbot.system_chat(db, to)
            msg = Message(chat_id=chat.id, sender_id=bot.id, kind="gift", text=text.strip(),
                          extra=extra)
            db.add(msg)
            db.commit()
            db.refresh(msg)
            await deliver(db, chat, msg, bot)
        else:
            chat = _direct_chat(db, giver.id, to.id)
            msg = Message(chat_id=chat.id, sender_id=giver.id, kind="gift", text=text.strip(),
                          extra=extra)
            db.add(msg)
            db.commit()
            db.refresh(msg)
            await deliver(db, chat, msg, giver)
        from app.realtime import manager
        await manager.send_to_users([to.id], {"type": "gift_received", "gift": info})
    return ug


@gifts_router.post("/gifts/send", status_code=201)
async def send_gift(data: GiftSendIn, db: Session = Depends(get_db),
                    me: User = Depends(get_current_user)):
    g = get_gift(db, data.gift_id)
    if g is None:
        raise HTTPException(status_code=404, detail="Подарок не найден")
    st = gift_status(_gift_rows(db)[data.gift_id])
    if st == "soon":
        raise HTTPException(status_code=410, detail="Этот подарок ещё не в продаже")
    if st != "on_sale":
        raise HTTPException(status_code=410, detail="Этот подарок больше не продаётся")
    to = db.query(User).filter(User.id == data.to_user_id).first()
    if to is None or to.is_bot or to.banned:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    if to.id == me.id and not is_premium(me):
        raise HTTPException(status_code=403,
                            detail="Дарить подарки себе можно с Connecto Premium")
    if to.id != me.id and (is_blocked(db, to.id, me.id) or is_blocked(db, me.id, to.id)):
        raise HTTPException(status_code=403, detail="Нельзя подарить подарок этому пользователю")
    if g.get("supply") and _sold(db, g["id"]) >= g["supply"]:
        raise HTTPException(status_code=410, detail="Этот лимитированный подарок закончился")
    target_name = to.display_name or to.username
    spend(db, me, g["price"], "gift",
          f"Подарок «{g['title']}» " + ("себе" if to.id == me.id else f"для {target_name}"))
    ug = await create_gift(db, g, to, me, data.text, data.anonymous)
    _ws_me([me.id])
    return {"gift": gift_dict(db, ug, me.id), "balance": int(me.coins or 0)}


@gifts_router.get("/users/{user_id}/gifts")
def user_gifts(user_id: str, db: Session = Depends(get_db),
               me: User = Depends(get_current_user)):
    owner = db.query(User).filter(User.id == user_id).first()
    if owner is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    mine = owner.id == me.id
    if not mine and not allowed(db, owner, me.id, "gifts"):
        return {"gifts": [], "count": 0, "hidden_by_privacy": True}
    q = db.query(UserGift).filter(UserGift.to_id == owner.id, UserGift.converted == False)  # noqa: E712
    if not mine:
        q = q.filter(UserGift.hidden == False)  # noqa: E712
    rows = q.all()
    # закреплённые — сверху, дальше уникальные и дорогие, среди равных — новее
    rows.sort(key=lambda r: (not r.pinned, not r.upgraded, -(r.price or 0),
                             -(as_utc(r.created_at).timestamp() if r.created_at else 0)))
    users = {u.id: u for u in db.query(User).filter(
        User.id.in_({r.from_id for r in rows if r.from_id})).all()}
    items = [gift_dict(db, r, me.id, users) for r in rows[:300]]
    return {"gifts": items, "count": len(rows),
            "value": sum(int(i["value"]) for i in items)}


def _own_gift(db: Session, gift_id: str, me: User) -> UserGift:
    ug = db.query(UserGift).filter(UserGift.id == gift_id).first()
    if ug is None or ug.to_id != me.id or ug.converted:
        raise HTTPException(status_code=404, detail="Подарок не найден")
    return ug


class HideIn(BaseModel):
    hidden: bool = True


@gifts_router.put("/gifts/{gift_id}/hide")
def hide_gift(gift_id: str, data: HideIn, db: Session = Depends(get_db),
              me: User = Depends(get_current_user)):
    ug = _own_gift(db, gift_id, me)
    ug.hidden = data.hidden
    db.commit()
    return gift_dict(db, ug, me.id)


class PinIn(BaseModel):
    pinned: bool = True


@gifts_router.put("/gifts/{gift_id}/pin")
def pin_gift(gift_id: str, data: PinIn, db: Session = Depends(get_db),
             me: User = Depends(get_current_user)):
    ug = _own_gift(db, gift_id, me)
    if data.pinned and not ug.pinned:
        n = db.query(UserGift).filter(UserGift.to_id == me.id, UserGift.pinned == True,  # noqa: E712
                                      UserGift.converted == False).count()  # noqa: E712
        if n >= MAX_PINNED_GIFTS:
            raise HTTPException(status_code=400,
                                detail=f"Закрепить можно до {MAX_PINNED_GIFTS} подарков")
    ug.pinned = data.pinned
    if data.pinned:
        ug.hidden = False
    db.commit()
    return gift_dict(db, ug, me.id)


@gifts_router.post("/gifts/{gift_id}/upgrade")
def upgrade_gift(gift_id: str, db: Session = Depends(get_db),
                 me: User = Depends(get_current_user)):
    """Улучшить до уникального: случайный фон, узор и номер. Обмен после этого недоступен."""
    import random
    ug = _own_gift(db, gift_id, me)
    if ug.upgraded:
        raise HTTPException(status_code=400, detail="Подарок уже уникальный")
    g = get_gift(db, ug.gift_id) or {"title": "Подарок", "price": ug.price}
    cost = upgrade_cost(int(ug.price or g["price"]))
    spend(db, me, cost, "upgrade", f"Улучшение «{g['title']}»")
    rnd = random.SystemRandom()
    b = rnd.choices(BACKDROPS, weights=[x["w"] for x in BACKDROPS])[0]
    p = rnd.choices(PATTERNS, weights=[x["w"] for x in PATTERNS])[0]
    ug.upgraded = True
    ug.backdrop = b["id"]
    ug.pattern = p["id"]
    ug.upgrade_cost = cost
    ug.unique_no = db.query(UserGift).filter(UserGift.gift_id == ug.gift_id,
                                             UserGift.upgraded == True).count() + 1  # noqa: E712
    db.commit()
    db.refresh(ug)
    return {"gift": gift_dict(db, ug, me.id), "balance": int(me.coins or 0)}


@gifts_router.get("/gifts/upgrade_info")
def upgrade_catalog(me: User = Depends(get_current_user)):
    return {
        "backdrops": [{"id": b["id"], "name": b["name"], "colors": b["colors"],
                       "pct": _pct(b["w"], _BW)} for b in BACKDROPS],
        "patterns": [{"id": p["id"], "name": p["name"], "symbol": p["symbol"],
                      "pct": _pct(p["w"], _PW)} for p in PATTERNS],
    }


@gifts_router.post("/gifts/{gift_id}/convert")
def convert_gift(gift_id: str, db: Session = Depends(get_db),
                 me: User = Depends(get_current_user)):
    ug = _own_gift(db, gift_id, me)
    if ug.upgraded:
        raise HTTPException(status_code=400, detail="Уникальный подарок нельзя обменять")
    orig_price = int(ug.price or g["price"])
    value = int(orig_price * CONVERT_RATE)
    fee = max(0, orig_price - value)
    ug.converted = True
    add_coins(db, me, value, "convert", f"Обмен подарка «{g['title']}»")
    try:
        from app.config import ADMIN_EMAIL
        admin_user = db.query(User).filter(User.is_admin == True).first()
        if not admin_user and ADMIN_EMAIL:
            admin_user = db.query(User).filter(User.email == ADMIN_EMAIL.lower()).first()
        if admin_user and fee > 0:
            add_coins(db, admin_user, fee, "market_commission", f"Комиссия с подарка «{g['title']}» от {me.username}")
    except Exception:
        pass
    db.commit()
    return {"coins": value, "balance": int(me.coins or 0)}


def profile_counts(db: Session, owner: User, viewer_id: str) -> dict:
    """Счётчики для профиля: подарки, публикации, есть ли активные истории."""
    from app.models.social import Story
    from app.routers.stories import can_see
    now = _now()
    gifts = 0
    if owner.id == viewer_id or allowed(db, owner, viewer_id, "gifts"):
        q = db.query(UserGift).filter(UserGift.to_id == owner.id,
                                      UserGift.converted == False)  # noqa: E712
        if owner.id != viewer_id:
            q = q.filter(UserGift.hidden == False)  # noqa: E712
        gifts = q.count()
    stories = (db.query(Story).filter(Story.user_id == owner.id, Story.deleted_at.is_(None))
               .filter((Story.pinned == True) | (Story.expires_at > now))  # noqa: E712
               .all())
    visible = [s for s in stories if can_see(db, s, owner, viewer_id)]
    active = [s for s in visible if as_utc(s.expires_at) > now]
    return {"gifts_count": gifts,
            "posts_count": sum(1 for s in visible if s.pinned),
            "has_stories": bool(active)}
