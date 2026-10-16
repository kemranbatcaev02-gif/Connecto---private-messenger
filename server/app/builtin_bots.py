"""Встроенные полезные боты Connecto: погода, курсы, факты и котики, переводчик.

Работают прямо на сервере (без Bot API и токенов): человек пишет боту в личку —
сервер отвечает от его имени. Данные берутся из бесплатных API (см. app/extapi.py).
"""
import asyncio
import json
import re
import secrets
import time
from datetime import date

from sqlalchemy import func
from sqlalchemy.orm import Session

from app import extapi
from app.core.security import hash_password
from app.database import SessionLocal
from app.models.chat import Chat, ChatMember, Message
from app.models.user import User

BOTS = [
    {
        "key": "weather", "handles": ["weatherbot", "pogodabot", "connecto_weather_bot"],
        "name": "Погода", "emoji": "🌤",
        "bio": "Погода сейчас и на 3 дня. Напиши город или пришли геопозицию.",
        "commands": [{"command": "start", "description": "Как пользоваться"},
                     {"command": "moscow", "description": "Погода в Москве"}],
    },
    {
        "key": "rates", "handles": ["ratesbot", "kursbot", "connecto_rates_bot"],
        "name": "Курсы валют", "emoji": "💱",
        "bio": "Курсы ЦБ РФ и криптовалют, конвертер: «100 usd», «50 евро в рубли», «btc».",
        "commands": [{"command": "rates", "description": "Главные курсы"},
                     {"command": "crypto", "description": "Криптовалюты"},
                     {"command": "start", "description": "Как пользоваться"}],
    },
    {
        "key": "fun", "handles": ["funbot", "factsbot", "connecto_fun_bot"],
        "name": "Факты и котики", "emoji": "🐱",
        "bio": "Случайные факты, шутки, советы, котики, собаки и лисы.",
        "commands": [{"command": "fact", "description": "Интересный факт"},
                     {"command": "joke", "description": "Шутка"},
                     {"command": "advice", "description": "Совет"},
                     {"command": "cat", "description": "Котик"},
                     {"command": "dog", "description": "Собака"},
                     {"command": "fox", "description": "Лиса"}],
    },
    {
        "key": "translate", "handles": ["translatebot", "perevodbot", "connecto_translate_bot"],
        "name": "Переводчик", "emoji": "🌍",
        "bio": "Пришли текст — переведу. Русский ↔ английский, другие языки — /to de.",
        "commands": [{"command": "to", "description": "Язык перевода: /to en, /to de…"},
                     {"command": "langs", "description": "Список языков"},
                     {"command": "start", "description": "Как пользоваться"}],
    },
]

_ids: dict[str, str] = {}          # user_id бота → key
_tasks: set = set()
_tr_target: dict[str, str] = {}    # человек → язык перевода
_rate: dict[str, list[float]] = {}


def _email(key: str) -> str:
    return f"builtin-{key}@bots.connecto.local"


def _taken(db: Session, h: str) -> bool:
    return bool(db.query(User).filter(func.lower(User.username) == h.lower()).first()
                or db.query(User).filter(func.lower(User.handle) == h.lower()).first()
                or db.query(Chat).filter(func.lower(Chat.handle) == h.lower()).first())


def ensure_bots(db: Session) -> None:
    """Создать ботов при старте сервера (если их ещё нет) и запомнить их id."""
    _ids.clear()
    for spec in BOTS:
        try:
            bot = _ensure_one(db, spec)
        except Exception:
            # другой процесс сервера создал бота одновременно с нами — берём его
            db.rollback()
            bot = db.query(User).filter(User.email == _email(spec["key"])).first()
        if bot is not None:
            _ids[bot.id] = spec["key"]


def _ensure_one(db: Session, spec: dict) -> User:
    bot = db.query(User).filter(User.email == _email(spec["key"])).first()
    if bot is None:
        handle = next((h for h in spec["handles"] if not _taken(db, h)),
                      f"cx{spec['key']}{secrets.token_hex(2)}bot")
        bot = User(username=handle, handle=handle, email=_email(spec["key"]),
                   password_hash=hash_password(secrets.token_hex(24)),
                   display_name=spec["name"], is_bot=True, is_verified=True)
        db.add(bot)
    bot.bio = spec["bio"]
    bot.bot_commands = json.dumps(spec["commands"], ensure_ascii=False)
    db.commit()
    db.refresh(bot)
    return bot


def list_bots(db: Session) -> list[dict]:
    if not _ids:
        ensure_bots(db)
    users = {u.id: u for u in db.query(User).filter(User.id.in_(list(_ids))).all()}
    out = []
    for spec in BOTS:
        bid = next((i for i, k in _ids.items() if k == spec["key"]), None)
        u = users.get(bid) if bid else None
        if u is None:
            continue
        out.append({"id": u.id, "key": spec["key"], "handle": u.handle or u.username,
                    "display_name": u.display_name, "bio": u.bio, "emoji": spec["emoji"],
                    "avatar_url": u.avatar_url})
    return out


# ─────────────────────────────── приём сообщений ───────────────────────────────

def dispatch(db: Session, chat: Chat, msg: Message, sender: User | None) -> None:
    """Вызывается из deliver(): личка с встроенным ботом — отвечаем в фоне."""
    if sender is None or sender.is_bot or chat.type != "direct":
        return
    if not _ids:
        ensure_bots(db)
    if msg.kind not in ("text", "location") or msg.enc:
        return
    bot_id = next((m.user_id for m in db.query(ChatMember).filter(ChatMember.chat_id == chat.id)
                   if m.user_id in _ids), None)
    if bot_id is None:
        return
    # не больше 20 сообщений ботам в минуту от одного человека
    now = time.time()
    arr = [t for t in _rate.get(sender.id, []) if now - t < 60]
    if len(arr) >= 20:
        return
    arr.append(now)
    _rate[sender.id] = arr
    job = {"chat_id": chat.id, "bot_id": bot_id, "key": _ids[bot_id], "user_id": sender.id,
           "kind": msg.kind, "text": (msg.text or "").strip()[:2000]}
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        return
    t = loop.create_task(_run(job))
    _tasks.add(t)
    t.add_done_callback(_tasks.discard)


async def _run(job: dict) -> None:
    from app.messaging import deliver, member_ids
    from app.realtime import manager
    db = SessionLocal()
    try:
        chat = db.query(Chat).filter(Chat.id == job["chat_id"]).first()
        bot = db.query(User).filter(User.id == job["bot_id"]).first()
        if chat is None or bot is None:
            return
        try:
            await manager.send_to_users([job["user_id"]], {
                "type": "typing", "chat_id": chat.id, "user_id": bot.id,
                "name": bot.display_name, "state": "typing"})
        except Exception:
            pass
        handler = HANDLERS.get(job["key"])
        try:
            replies = await handler(job) if handler else []
        except Exception:
            replies = [{"text": "😔 Сервис сейчас не отвечает. Попробуй чуть позже."}]
        for r in replies:
            media = r.get("image")
            if media and media.startswith("http"):
                try:
                    media = (await extapi.download(media, 8 * 1024 * 1024))["url"]
                except Exception:
                    pass   # оставим внешнюю ссылку
            m = Message(chat_id=chat.id, sender_id=bot.id,
                        kind="image" if media else "text",
                        text=(r.get("text") or "")[:4000], media_url=media)
            db.add(m)
            db.commit()
            db.refresh(m)
            await deliver(db, chat, m, bot)
        try:
            await manager.send_to_users(member_ids(db, chat.id), {
                "type": "typing", "chat_id": chat.id, "user_id": bot.id, "state": "stop"})
        except Exception:
            pass
    finally:
        db.close()


def _cmd(text: str) -> tuple[str, str]:
    """'/to@bot de' → ('to', 'de'); обычный текст → ('', текст)."""
    if not text.startswith("/"):
        return "", text
    head, _, rest = text[1:].partition(" ")
    return head.split("@")[0].lower(), rest.strip()


# ─────────────────────────────── погода ───────────────────────────────

_WD = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]


def _t(v) -> str:
    v = round(float(v))
    return f"+{v}°" if v > 0 else f"{v}°"


async def _weather(job: dict) -> list[dict]:
    text = job["text"]
    place = None
    if job["kind"] == "location":
        try:
            lat, lon = (float(x) for x in text.split(",")[:2])
            place = {"name": "Твоё место", "lat": lat, "lon": lon, "country": "", "region": ""}
        except Exception:
            return [{"text": "Не получилось прочитать геопозицию 🤔"}]
    else:
        cmd, rest = _cmd(text)
        if cmd in ("start", "help"):
            return [{"text": "🌤 Привет! Напиши название города — пришлю погоду сейчас и на 3 дня.\n\n"
                             "Например: «Москва», «Казань», «Лондон».\n"
                             "Или отправь геопозицию через 📎 → «Место»."}]
        if cmd == "moscow":
            rest = "Москва"
        elif cmd:
            rest = rest or cmd
        city = re.sub(r"^(погода|weather)\s*(в|во|in)?\s*", "", rest, flags=re.IGNORECASE).strip()
        if not city:
            return [{"text": "Напиши город, например: «Сочи» 🙂"}]
        place = await extapi.geocode(city[:80])
        if place is None:
            return [{"text": f"Не нашла город «{city[:40]}» 🤔 Проверь написание."}]
    d = await extapi.forecast(place["lat"], place["lon"])
    cur = d.get("current") or {}
    e, word = extapi.weather_word(int(cur.get("weather_code") or 0))
    where = ", ".join(x for x in (place["name"], place.get("country")) if x)
    lines = [f"{e} {where}",
             f"Сейчас: {_t(cur.get('temperature_2m', 0))}, {word} "
             f"(ощущается как {_t(cur.get('apparent_temperature', 0))})",
             f"💨 ветер {round(float(cur.get('wind_speed_10m') or 0))} м/с · "
             f"💧 влажность {round(float(cur.get('relative_humidity_2m') or 0))}%", ""]
    dd = d.get("daily") or {}
    for i, day in enumerate((dd.get("time") or [])[:3]):
        try:
            de, _ = extapi.weather_word(int(dd["weather_code"][i]))
            label = ["Сегодня", "Завтра"][i] if i < 2 else \
                f"{_WD[date.fromisoformat(day).weekday()]} {day[8:10]}.{day[5:7]}"
            rain = (dd.get("precipitation_probability_max") or [None] * 3)[i]
            lines.append(f"{label}: {de} {_t(dd['temperature_2m_min'][i])}…"
                         f"{_t(dd['temperature_2m_max'][i])}"
                         + (f", осадки {rain}%" if rain is not None else ""))
        except Exception:
            continue
    return [{"text": "\n".join(lines).strip()}]


# ─────────────────────────────── курсы ───────────────────────────────

ALIASES = {
    "USD": ("usd", "$", "доллар", "долл", "бакс"), "EUR": ("eur", "€", "евро"),
    "RUB": ("rub", "₽", "руб", "рубл"), "CNY": ("cny", "юан", "¥"), "GBP": ("gbp", "фунт", "£"),
    "KZT": ("kzt", "тенге", "₸"), "TRY": ("try", "лир", "лира", "лиры", "лирах"), "UAH": ("uah", "грив"),
    "BYN": ("byn", "белорус"), "KGS": ("kgs", "сом", "сома", "сомов"), "AMD": ("amd", "драм"),
    "GEL": ("gel", "лари"), "UZS": ("uzs", "сум", "сума", "сумов"), "JPY": ("jpy", "иен", "йен"),
    "CHF": ("chf", "франк"), "AED": ("aed", "дирхам"), "INR": ("inr", "рупи"),
    "BTC": ("btc", "биткоин", "биток", "bitcoin"), "ETH": ("eth", "эфир", "ethereum"),
    "TON": ("ton", "тон", "тона", "toncoin", "тонкоин"), "USDT": ("usdt", "тезер", "tether"), "SOL": ("sol", "солана"),
    "DOGE": ("doge", "доге", "dogecoin", "догикоин"), "BNB": ("bnb",), "XRP": ("xrp",), "LTC": ("ltc", "лайткоин"),
    "TRX": ("trx", "трон"), "NOT": ("notcoin", "ноткоин"),
}


def _code(word: str) -> str | None:
    w = word.lower().strip(" .,!?")
    if not w:
        return None
    if w.upper() in ALIASES:
        return w.upper()
    for code, keys in ALIASES.items():
        # короткие (≤3 буквы) — только целым словом: «тон», но не «тонна»
        if any(w == k or (len(k) > 3 and w.startswith(k)) for k in keys):
            return code
    for code, keys in ALIASES.items():
        if any(len(k) == 3 and w.startswith(k) and len(w) <= len(k) + 3
               and k not in ("тон", "дог", "сом", "лир", "сум") for k in keys):
            return code
    return None


def _norm_amount(q: str) -> str:
    """«курс доллара» → «доллара», «$100» → «100 $», «1 000,5» → «1000.5», «1,000» → «1000»."""
    q = re.sub(r"^\s*(курс\w*|сколько\s+стоит|цена)\s+", "", q.strip())
    q = re.sub(r"(?<=\d)[ \u00a0](?=\d{3}\b)", "", q)
    q = re.sub(r"(?<=\d),(?=\d{3}\b)", "", q)
    q = q.replace(",", ".")
    m = re.match(r"^\s*([$€₽£¥₸])\s*(\d+(?:\.\d+)?)(.*)$", q)
    if m:
        q = f"{m.group(2)} {m.group(1)}{m.group(3)}"
    return q


def _num(v: float) -> str:
    if v >= 100:
        s = f"{v:,.2f}"
    elif v >= 1:
        s = f"{v:,.4f}".rstrip("0").rstrip(".")
    else:
        s = f"{v:.6f}".rstrip("0").rstrip(".")
    return s.replace(",", " ").replace(".", ",")


def _arrow(now: float, prev: float) -> str:
    if prev <= 0 or abs(now - prev) < 1e-9:
        return ""
    ch = (now - prev) / prev * 100
    return f" {'▲' if ch > 0 else '▼'}{abs(ch):.2f}%"


async def _rates(job: dict) -> list[dict]:
    cmd, rest = _cmd(job["text"])
    if cmd in ("start", "help"):
        return [{"text": "💱 Курсы валют ЦБ РФ и криптовалют.\n\n"
                         "• /rates — главные курсы\n• /crypto — криптовалюты\n"
                         "• «100 usd» — перевести в рубли\n• «50 евро в доллары»\n"
                         "• «0.1 btc» — биткоин в долларах и рублях"}]
    if cmd == "rates" or (not cmd and re.fullmatch(r"(курс[ыа]?|валют[ыа]?)?", rest.lower())):
        cbr = await extapi.cbr_rates()
        lines = [f"💱 Курсы ЦБ РФ на {cbr.get('_date', '')}"]
        for c, flag in (("USD", "🇺🇸"), ("EUR", "🇪🇺"), ("CNY", "🇨🇳"), ("GBP", "🇬🇧"),
                        ("KZT", "🇰🇿"), ("TRY", "🇹🇷")):
            v = cbr.get(c)
            if v:
                lines.append(f"{flag} 1 {c} = {_num(v['value'])} ₽{_arrow(v['value'], v['prev'])}")
        try:
            cr = await extapi.crypto_prices(["BTC", "ETH", "TON"])
            if cr:
                lines.append("")
                for c, v in cr.items():
                    lines.append(f"🪙 {c} = ${_num(v.get('usd', 0))}")
        except Exception:
            pass
        return [{"text": "\n".join(lines)}]
    if cmd == "crypto":
        cr = await extapi.crypto_prices(list(extapi.CRYPTO))
        lines = ["🪙 Криптовалюты (CoinGecko)"]
        for c, v in cr.items():
            chg = v.get("usd_24h_change")
            ch = f" {'▲' if chg > 0 else '▼'}{abs(chg):.1f}%" if isinstance(chg, (int, float)) else ""
            lines.append(f"{c}: ${_num(v.get('usd', 0))} · {_num(v.get('rub', 0))} ₽{ch}")
        return [{"text": "\n".join(lines)}]
    q = _norm_amount((rest if not cmd else f"{cmd} {rest}").lower())
    m = re.match(r"^\s*(\d+(?:\.\d+)?)?\s*([^\d\s]+)(?:\s+(?:в|во|to|in|на)?\s*([^\d\s]+))?\s*$", q)
    if not m:
        return [{"text": "Не поняла 🤔 Напиши, например: «100 usd» или «50 евро в доллары»."}]
    amount = float(m.group(1) or 1)
    src = _code(m.group(2))
    dst = _code(m.group(3)) if m.group(3) else None
    if src is None:
        return [{"text": f"Не знаю валюту «{m.group(2)[:20]}» 🤔"}]
    cbr = await extapi.cbr_rates()

    async def rub_per(code: str) -> float | None:
        if code in cbr:
            return cbr[code]["value"]
        if code in extapi.CRYPTO:
            p = (await extapi.crypto_prices([code])).get(code) or {}
            return float(p.get("rub") or 0) or None
        return None

    if dst is None:
        dst = "USD" if src == "RUB" else "RUB"
    a, b = await rub_per(src), await rub_per(dst)
    if not a or not b:
        return [{"text": "Для этой валюты сейчас нет курса 😔"}]
    res = amount * a / b
    lines = [f"💱 {_num(amount)} {src} = {_num(res)} {dst}"]
    if src in extapi.CRYPTO and dst == "RUB" and "USD" in cbr:
        lines.append(f"≈ ${_num(res / cbr['USD']['value'])}")
    lines.append(f"\nКурс ЦБ на {cbr.get('_date', '')}" if src not in extapi.CRYPTO
                 and dst not in extapi.CRYPTO else "\nКурс CoinGecko")
    return [{"text": "\n".join(lines)}]


# ─────────────────────────────── факты и котики ───────────────────────────────

async def _ru(text: str) -> str:
    try:
        return (await extapi.translate(text, "ru"))["text"]
    except Exception:
        return text


async def _fun(job: dict) -> list[dict]:
    cmd, rest = _cmd(job["text"])
    s = (cmd or rest).lower()
    if cmd in ("start", "help") or not s:
        return [{"text": "🐱 Что умею:\n\n/fact — интересный факт\n/joke — шутка\n"
                         "/advice — совет\n/cat — котик\n/dog — собака\n/fox — лиса\n\n"
                         "Можно и словами: «кот», «факт», «шутка»."}]
    if s.startswith(("fact", "факт")):
        return [{"text": "💡 " + await _ru(await extapi.fact())}]
    if s.startswith(("joke", "шут", "анекдот")):
        return [{"text": "😄 " + await _ru(await extapi.joke())}]
    if s.startswith(("advice", "совет")):
        return [{"text": "🧭 " + await _ru(await extapi.advice())}]
    for kind, keys in (("cat", ("cat", "кот", "кош", "котик")), ("dog", ("dog", "соба", "пёс", "пес")),
                       ("fox", ("fox", "лис"))):
        if s.startswith(keys):
            cap = {"cat": "🐱 Держи котика!", "dog": "🐶 Держи пёселя!", "fox": "🦊 Держи лису!"}[kind]
            return [{"image": await extapi.animal(kind), "text": cap}]
    return [{"text": "Не поняла 🙂 Попробуй /fact, /joke, /cat, /dog или /fox."}]


# ─────────────────────────────── переводчик ───────────────────────────────

async def _translate(job: dict) -> list[dict]:
    cmd, rest = _cmd(job["text"])
    uid = job["user_id"]
    if cmd in ("start", "help"):
        return [{"text": "🌍 Пришли любой текст — переведу.\n\n"
                         "По умолчанию: русский → английский, другие языки → русский.\n"
                         "/to de — всегда переводить на немецкий (en, fr, es, tr, zh…)\n"
                         "/to auto — снова автоматически\n/langs — список языков"}]
    if cmd == "langs":
        return [{"text": "Языки:\n" + "\n".join(f"{k} — {v}" for k, v in extapi.LANGS.items())}]
    if cmd == "to":
        code = rest.lower()[:5]
        if code in ("", "auto", "авто"):
            _tr_target.pop(uid, None)
            return [{"text": "Готово: перевожу автоматически (ru ↔ en)."}]
        if code not in extapi.LANGS:
            return [{"text": "Не знаю такой язык 🤔 Список: /langs"}]
        _tr_target[uid] = code
        return [{"text": f"Готово: перевожу на {extapi.LANGS[code]} ({code})."}]
    text = rest if not cmd else job["text"]
    if not text:
        return [{"text": "Пришли текст для перевода 🙂"}]
    to = _tr_target.get(uid) or ("en" if extapi.guess_lang(text) == "ru" else "ru")
    r = await extapi.translate(text, to)
    return [{"text": f"{r['text']}\n\n— {r.get('from', '?')} → {to}"}]


HANDLERS = {"weather": _weather, "rates": _rates, "fun": _fun, "translate": _translate}
