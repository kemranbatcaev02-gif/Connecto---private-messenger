"""Бесплатные внешние API (из github.com/public-apis/public-apis) для Connecto.

GIF — GIPHY (ключ) или nekos.best (без ключа); перевод — LibreTranslate (свой),
Google gtx и MyMemory; музыка — iTunes Search и Deezer (превью 30 с);
погода — Open-Meteo; курсы — ЦБ РФ (cbr-xml-daily) и CoinGecko;
факты/шутки/советы — Useless Facts, JokeAPI, Advice Slip; котики/собаки/лисы —
TheCatAPI, Dog CEO, RandomFox.

Все запросы идут с сервера: ключи не попадают в приложение, а ответы кэшируются.
"""
import os
import re
import time
import uuid
from urllib.parse import urlparse

import httpx

from app.config import settings

UA = {"User-Agent": "Connecto/1.0 (messenger; +https://github.com/public-apis/public-apis)"}
TIMEOUT = httpx.Timeout(8.0, connect=5.0)
MEDIA_DIR = "media"


class ExtError(Exception):
    """Сервис недоступен / ничего не нашлось — текст можно показать человеку."""


# ─────────────────────────────── общее ───────────────────────────────

_cache: dict[str, tuple[float, object]] = {}


def _cached(key: str, ttl: float):
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < ttl:
        return hit[1]
    return None


def _store(key: str, value):
    if len(_cache) > 2000:
        # простая чистка: выкидываем старейшую половину
        for k, _ in sorted(_cache.items(), key=lambda kv: kv[1][0])[:1000]:
            _cache.pop(k, None)
    _cache[key] = (time.time(), value)
    return value


async def get_json(url: str, params: dict | None = None, headers: dict | None = None):
    async with httpx.AsyncClient(timeout=TIMEOUT, headers={**UA, **(headers or {})},
                                 follow_redirects=True) as c:
        r = await c.get(url, params=params)
        r.raise_for_status()
        return r.json()


# ─────────────────────────────── скачивание к себе ───────────────────────────────

# Откуда разрешаем «забрать к себе» файл по ссылке (чтобы сервер не стал прокси куда угодно)
ALLOWED_HOSTS = (
    "giphy.com", "nekos.best", "mzstatic.com", "itunes.apple.com", "dzcdn.net",
    "deezer.com", "thecatapi.com", "cdn2.thecatapi.com", "dog.ceo", "randomfox.ca",
    "cataas.com",
)
_EXT = {"image/gif": ".gif", "image/webp": ".webp", "image/png": ".png", "image/jpeg": ".jpg",
        "image/jpg": ".jpg", "audio/mpeg": ".mp3", "audio/mp3": ".mp3", "audio/mp4": ".m4a",
        "audio/x-m4a": ".m4a", "audio/m4a": ".m4a", "audio/aac": ".aac", "video/mp4": ".mp4"}


def host_allowed(url: str) -> bool:
    try:
        u = urlparse(url)
    except Exception:
        return False
    if u.scheme not in ("http", "https") or not u.hostname:
        return False
    h = u.hostname.lower()
    return any(h == a or h.endswith("." + a) for a in ALLOWED_HOSTS)


async def download(url: str, max_bytes: int = 12 * 1024 * 1024,
                   kinds: tuple[str, ...] = ("image/", "audio/", "video/")) -> dict:
    """Скачать файл в media/ и вернуть {url, size, type}. Одинаковые ссылки — один файл.

    Каждый переход по редиректу снова проверяется по списку разрешённых сайтов,
    а сохраняем только картинки/звук/видео (никаких html/svg на нашем домене)."""
    if not host_allowed(url):
        raise ExtError("Эту ссылку загрузить нельзя")
    key = f"dl:{url}"
    hit = _cached(key, 7 * 24 * 3600)
    if hit and hit["type"].startswith(kinds) and \
            os.path.exists(os.path.join(MEDIA_DIR, os.path.basename(hit["url"]))):
        return hit
    os.makedirs(MEDIA_DIR, exist_ok=True)
    async with httpx.AsyncClient(timeout=httpx.Timeout(20.0, connect=6.0), headers=UA,
                                 follow_redirects=False) as c:
        cur = url
        for _ in range(5):
            async with c.stream("GET", cur) as r:
                if r.status_code in (301, 302, 303, 307, 308):
                    nxt = r.headers.get("location") or ""
                    cur = str(httpx.URL(cur).join(nxt))
                    if not host_allowed(cur):
                        raise ExtError("Эту ссылку загрузить нельзя")
                    continue
                if r.status_code != 200:
                    raise ExtError("Файл недоступен")
                ctype = (r.headers.get("content-type") or "").split(";")[0].strip().lower()
                ext = _EXT.get(ctype)
                if ext is None or not ctype.startswith(kinds):
                    raise ExtError("Этот файл загрузить нельзя")
                name = f"{uuid.uuid4().hex}{ext}"
                path = os.path.join(MEDIA_DIR, name)
                size = 0
                try:
                    with open(path, "wb") as f:
                        async for chunk in r.aiter_bytes(64 * 1024):
                            size += len(chunk)
                            if size > max_bytes:
                                raise ExtError("Файл слишком большой")
                            f.write(chunk)
                except Exception:
                    try:
                        os.remove(path)
                    except OSError:
                        pass
                    raise
                return _store(key, {"url": f"/media/{name}", "size": size, "type": ctype})
    raise ExtError("Файл недоступен")


# ─────────────────────────────── GIF ───────────────────────────────

# Реакции nekos.best (без ключа): русское название → категория
NEKOS = [
    ("Обнять", "hug"), ("Привет", "wave"), ("Смех", "laugh"), ("Плачу", "cry"),
    ("Танец", "dance"), ("Радость", "happy"), ("Улыбка", "smile"), ("Класс", "thumbsup"),
    ("Фейспалм", "facepalm"), ("Не знаю", "shrug"), ("Сплю", "sleep"), ("Смущение", "blush"),
    ("Дай пять", "highfive"), ("Подмиг", "wink"), ("Скучно", "bored"), ("Думаю", "think"),
    ("Да", "nod"), ("Нет", "nope"), ("Погладить", "pat"), ("Поцелуй", "kiss"),
    ("Обижка", "pout"), ("Зевок", "yawn"), ("Бегу", "run"), ("Ням", "nom"),
]
_NEKO_CATS = {c for _, c in NEKOS}


def gif_provider() -> str:
    return "giphy" if settings.giphy_key else "nekos"


def _giphy_item(g: dict) -> dict | None:
    im = g.get("images") or {}
    main = im.get("fixed_width") or im.get("downsized") or im.get("original") or {}
    small = im.get("fixed_width_small") or im.get("preview_gif") or main
    url = main.get("url")
    if not url:
        return None
    return {"id": g.get("id"), "title": g.get("title") or "", "url": url,
            "preview": small.get("url") or url,
            "w": int(main.get("width") or 200), "h": int(main.get("height") or 200)}


async def gifs(q: str, offset: int = 0, limit: int = 24) -> dict:
    """{provider, items:[{id,url,preview,w,h,title}], next, categories}"""
    q = (q or "").strip()
    limit = max(1, min(limit, 48))
    if settings.giphy_key:
        key = f"giphy:{q.lower()}:{offset}:{limit}"
        hit = _cached(key, 600)
        if hit is None:
            path = "search" if q else "trending"
            params = {"api_key": settings.giphy_key, "limit": limit, "offset": offset,
                      "rating": "pg-13", "bundle": "messaging_non_clips"}
            if q:
                params.update({"q": q, "lang": "ru"})
            try:
                d = await get_json(f"https://api.giphy.com/v1/gifs/{path}", params)
            except Exception:
                raise ExtError("GIF сейчас недоступны")
            items = [x for x in (_giphy_item(g) for g in d.get("data") or []) if x]
            pag = d.get("pagination") or {}
            nxt = offset + len(items)
            more = nxt < int(pag.get("total_count") or 0)
            hit = _store(key, {"provider": "giphy", "items": items,
                               "next": nxt if more and items else None})
        return {**hit, "categories": []}
    # без ключа — реакции nekos.best
    cat = q.lower()
    for ru, c in NEKOS:
        if cat == ru.lower():
            cat = c
    if cat not in _NEKO_CATS:
        cat = NEKOS[(offset // limit) % len(NEKOS)][1] if not q else _guess_neko(q)
    key = f"nekos:{cat}:{offset}"
    hit = _cached(key, 300)
    if hit is None:
        try:
            d = await get_json(f"https://nekos.best/api/v2/{cat}", {"amount": min(limit, 20)})
        except Exception:
            raise ExtError("GIF сейчас недоступны")
        items = []
        for i, r in enumerate(d.get("results") or []):
            u = r.get("url")
            if u:
                items.append({"id": f"{cat}-{offset}-{i}", "title": r.get("anime_name") or "",
                              "url": u, "preview": u, "w": 250, "h": 180})
        hit = _store(key, {"provider": "nekos", "items": items,
                           "next": offset + len(items) if items else None})
    return {**hit, "categories": [ru for ru, _ in NEKOS]}


def _guess_neko(q: str) -> str:
    s = q.lower()
    words = {
        "hug": ("обн", "hug"), "wave": ("прив", "пока", "hi", "hello", "bye"),
        "laugh": ("смех", "ржу", "лол", "ха", "lol", "laugh"), "cry": ("плач", "груст", "cry", "sad"),
        "dance": ("танц", "dance"), "happy": ("рад", "ура", "happy"),
        "thumbsup": ("класс", "ок", "норм", "лайк", "ok", "like"), "facepalm": ("фейс", "facepalm"),
        "shrug": ("хз", "не знаю", "shrug"), "sleep": ("спат", "сон", "сплю", "sleep", "night"),
        "kiss": ("поцел", "kiss", "люблю", "love"), "think": ("дума", "хм", "think"),
        "nope": ("нет", "no"), "nod": ("да", "yes"), "yawn": ("зев", "скуч"),
        "pat": ("глад", "pat"), "blush": ("смущ", "blush"),
    }
    for cat, keys in words.items():
        if any(k in s for k in keys):
            return cat
    return "happy"


# ─────────────────────────────── перевод ───────────────────────────────

LANGS = {
    "ru": "русский", "en": "английский", "de": "немецкий", "fr": "французский",
    "es": "испанский", "it": "итальянский", "pt": "португальский", "tr": "турецкий",
    "uk": "украинский", "kk": "казахский", "uz": "узбекский", "az": "азербайджанский",
    "hy": "армянский", "ka": "грузинский", "zh": "китайский", "ja": "японский",
    "ko": "корейский", "ar": "арабский", "pl": "польский", "be": "белорусский",
}
_CYR = re.compile(r"[а-яё]", re.IGNORECASE)
_LAT = re.compile(r"[a-z]", re.IGNORECASE)


def guess_lang(text: str) -> str:
    cyr = len(_CYR.findall(text))
    lat = len(_LAT.findall(text))
    return "ru" if cyr >= lat else "en"


async def translate(text: str, to: str = "ru", src: str = "auto") -> dict:
    """{text, from, to, provider}"""
    text = (text or "").strip()
    if not text:
        raise ExtError("Нечего переводить")
    text = text[:4500]
    to = (to or "ru").lower()[:5]
    key = f"tr:{src}:{to}:{text}"
    hit = _cached(key, 24 * 3600)
    if hit is not None:
        return hit
    errors = []
    # 1) свой LibreTranslate, если настроен
    if settings.libretranslate_url:
        try:
            async with httpx.AsyncClient(timeout=TIMEOUT, headers=UA) as c:
                r = await c.post(settings.libretranslate_url.rstrip("/") + "/translate", json={
                    "q": text, "source": src if src != "auto" else "auto", "target": to,
                    "format": "text", "api_key": settings.libretranslate_key or None})
                r.raise_for_status()
                d = r.json()
            out = d.get("translatedText")
            if out:
                det = (d.get("detectedLanguage") or {}).get("language") or src
                return _store(key, {"text": out, "from": det, "to": to,
                                    "provider": "libretranslate"})
        except Exception as e:  # noqa: BLE001
            errors.append(e)
    # 2) Google (gtx, без ключа)
    try:
        d = await get_json("https://translate.googleapis.com/translate_a/single",
                           {"client": "gtx", "sl": src, "tl": to, "dt": "t", "q": text})
        parts = [p[0] for p in (d[0] or []) if isinstance(p, list) and p and p[0]]
        if parts:
            det = d[2] if len(d) > 2 and isinstance(d[2], str) else src
            return _store(key, {"text": "".join(parts), "from": det, "to": to,
                                "provider": "google"})
    except Exception as e:  # noqa: BLE001
        errors.append(e)
    # 3) MyMemory (без ключа; язык источника угадываем)
    try:
        s = guess_lang(text) if src == "auto" else src
        if s == to:
            s = "en" if to == "ru" else "ru"
        params = {"q": text[:500], "langpair": f"{s}|{to}"}
        if settings.mymemory_email:
            params["de"] = settings.mymemory_email
        d = await get_json("https://api.mymemory.translated.net/get", params)
        out = ((d.get("responseData") or {}).get("translatedText") or "").strip()
        if out and "MYMEMORY WARNING" not in out.upper():
            return _store(key, {"text": out, "from": s, "to": to, "provider": "mymemory"})
    except Exception as e:  # noqa: BLE001
        errors.append(e)
    raise ExtError("Перевод сейчас недоступен")


# ─────────────────────────────── музыка ───────────────────────────────

def _itunes_item(r: dict) -> dict | None:
    prev = r.get("previewUrl")
    if not prev:
        return None
    art = (r.get("artworkUrl100") or "").replace("100x100bb", "600x600bb")
    return {"id": f"it{r.get('trackId')}", "title": r.get("trackName") or "",
            "artist": r.get("artistName") or "", "album": r.get("collectionName") or "",
            "cover": art or None, "preview": prev,
            "duration": int((r.get("trackTimeMillis") or 0) / 1000)}


def _deezer_item(r: dict) -> dict | None:
    prev = r.get("preview")
    if not prev:
        return None
    alb = r.get("album") or {}
    return {"id": f"dz{r.get('id')}", "title": r.get("title") or "",
            "artist": (r.get("artist") or {}).get("name") or "", "album": alb.get("title") or "",
            "cover": alb.get("cover_big") or alb.get("cover_medium"), "preview": prev,
            "duration": int(r.get("duration") or 0)}


async def music(q: str, limit: int = 25) -> list[dict]:
    q = (q or "").strip()
    if not q:
        return []
    key = f"mu:{q.lower()}:{limit}"
    hit = _cached(key, 3600)
    if hit is not None:
        return hit
    items: list[dict] = []
    try:
        d = await get_json("https://itunes.apple.com/search", {
            "term": q, "media": "music", "entity": "song", "limit": limit,
            "country": settings.music_country or "US"})
        items = [x for x in (_itunes_item(r) for r in d.get("results") or []) if x]
    except Exception:
        items = []
    if not items:
        try:
            d = await get_json("https://api.deezer.com/search", {"q": q, "limit": limit})
            items = [x for x in (_deezer_item(r) for r in d.get("data") or []) if x]
        except Exception:
            raise ExtError("Поиск музыки сейчас недоступен")
    return _store(key, items)


# ─────────────────────────────── погода ───────────────────────────────

WEATHER = [
    ((0,), "☀️", "ясно"), ((1, 2), "🌤", "малооблачно"), ((3,), "☁️", "облачно"),
    ((45, 48), "🌫", "туман"), ((51, 53, 55, 56, 57), "🌦", "морось"),
    ((61, 63, 65, 66, 67, 80, 81, 82), "🌧", "дождь"), ((71, 73, 75, 77, 85, 86), "🌨", "снег"),
    ((95, 96, 99), "⛈", "гроза"),
]


def weather_word(code: int) -> tuple[str, str]:
    for codes, e, t in WEATHER:
        if code in codes:
            return e, t
    return "🌡", "погода"


async def geocode(name: str) -> dict | None:
    key = f"geo:{name.lower()}"
    hit = _cached(key, 7 * 24 * 3600)
    if hit is not None:
        return hit or None
    d = await get_json("https://geocoding-api.open-meteo.com/v1/search",
                       {"name": name, "count": 1, "language": "ru", "format": "json"})
    res = (d.get("results") or [None])[0]
    out = None
    if res:
        out = {"name": res.get("name") or name, "lat": res.get("latitude"),
               "lon": res.get("longitude"), "country": res.get("country") or "",
               "region": res.get("admin1") or ""}
    _store(key, out or {})
    return out


async def forecast(lat: float, lon: float) -> dict:
    key = f"wx:{round(lat, 2)}:{round(lon, 2)}"
    hit = _cached(key, 600)
    if hit is not None:
        return hit
    d = await get_json("https://api.open-meteo.com/v1/forecast", {
        "latitude": lat, "longitude": lon, "timezone": "auto", "forecast_days": 3,
        "current": "temperature_2m,apparent_temperature,relative_humidity_2m,"
                   "weather_code,wind_speed_10m",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,"
                 "precipitation_probability_max",
        "wind_speed_unit": "ms"})
    return _store(key, d)


# ─────────────────────────────── курсы ───────────────────────────────

async def cbr_rates() -> dict:
    """Курсы ЦБ РФ: {'USD': {'value': рублей за 1, 'prev': ..., 'name': ...}, ..., 'RUB': 1}"""
    hit = _cached("cbr", 1800)
    if hit is not None:
        return hit
    d = await get_json("https://www.cbr-xml-daily.ru/daily_json.js")
    out = {"_date": d.get("Date", "")[:10], "RUB": {"value": 1.0, "prev": 1.0, "name": "Рубль"}}
    for code, v in (d.get("Valute") or {}).items():
        nom = float(v.get("Nominal") or 1)
        out[code] = {"value": float(v.get("Value")) / nom, "prev": float(v.get("Previous")) / nom,
                     "name": v.get("Name") or code}
    return _store("cbr", out)


CRYPTO = {"BTC": "bitcoin", "ETH": "ethereum", "TON": "the-open-network", "USDT": "tether",
          "SOL": "solana", "DOGE": "dogecoin", "BNB": "binancecoin", "XRP": "ripple",
          "LTC": "litecoin", "TRX": "tron", "NOT": "notcoin"}


async def crypto_prices(symbols: list[str]) -> dict:
    ids = [CRYPTO[s] for s in symbols if s in CRYPTO]
    if not ids:
        return {}
    key = "cg:" + ",".join(sorted(ids))
    hit = _cached(key, 120)
    if hit is None:
        d = await get_json("https://api.coingecko.com/api/v3/simple/price", {
            "ids": ",".join(ids), "vs_currencies": "usd,rub", "include_24hr_change": "true"})
        hit = _store(key, d)
    inv = {v: k for k, v in CRYPTO.items()}
    return {inv[i]: v for i, v in hit.items() if i in inv}


# ─────────────────────────────── развлечения ───────────────────────────────

async def fact() -> str:
    d = await get_json("https://uselessfacts.jsph.pl/api/v2/facts/random", {"language": "en"})
    return d.get("text") or ""


async def joke() -> str:
    d = await get_json("https://v2.jokeapi.dev/joke/Any", {
        "safe-mode": "", "blacklistFlags": "nsfw,religious,political,racist,sexist,explicit"})
    if d.get("type") == "twopart":
        return f"{d.get('setup', '')}\n\n— {d.get('delivery', '')}"
    return d.get("joke") or ""


async def advice() -> str:
    d = await get_json("https://api.adviceslip.com/advice", {"t": int(time.time())})
    return (d.get("slip") or {}).get("advice") or ""


async def animal(kind: str) -> str:
    if kind == "cat":
        d = await get_json("https://api.thecatapi.com/v1/images/search")
        return d[0]["url"]
    if kind == "dog":
        d = await get_json("https://dog.ceo/api/breeds/image/random")
        return d["message"]
    d = await get_json("https://randomfox.ca/floof/")
    return d["image"]

