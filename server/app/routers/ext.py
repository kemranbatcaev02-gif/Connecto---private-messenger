"""Внешние API для приложения: GIF, перевод, музыка для историй, полезные боты."""
import time

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app import extapi
from app.deps import get_db, get_current_user
from app.models.user import User

router = APIRouter(prefix="/ext", tags=["ext"])

# простой лимит: не больше N запросов в минуту на человека и вид запроса
_hits: dict[str, list[float]] = {}


def _limit(user: User, kind: str, per_min: int):
    now = time.time()
    k = f"{kind}:{user.id}"
    arr = [t for t in _hits.get(k, []) if now - t < 60]
    if len(arr) >= per_min:
        raise HTTPException(status_code=429, detail="Слишком часто — подожди минутку")
    arr.append(now)
    _hits[k] = arr


def _fail(e: Exception):
    if isinstance(e, extapi.ExtError):
        raise HTTPException(status_code=503, detail=str(e))
    raise HTTPException(status_code=503, detail="Сервис сейчас недоступен")


# ── GIF ──

@router.get("/gifs")
async def gifs(q: str = "", offset: int = 0, user: User = Depends(get_current_user)):
    _limit(user, "gif", 60)
    try:
        return await extapi.gifs(q[:80], max(0, offset))
    except Exception as e:  # noqa: BLE001
        _fail(e)


class Fetch(BaseModel):
    url: str = Field(min_length=8, max_length=1000)


@router.post("/gifs/import")
async def gif_import(data: Fetch, user: User = Depends(get_current_user)):
    """Забрать GIF к нам на сервер (так он откроется у всех и не пропадёт)."""
    _limit(user, "import", 30)
    try:
        r = await extapi.download(data.url, max_bytes=10 * 1024 * 1024,
                                 kinds=("image/", "video/"))
    except Exception as e:  # noqa: BLE001
        _fail(e)
    return {"url": r["url"], "size": r["size"]}


# ── перевод ──

class TranslateIn(BaseModel):
    text: str = Field(min_length=1, max_length=5000)
    to: str = Field(default="ru", max_length=5)


@router.post("/translate")
async def translate(data: TranslateIn, user: User = Depends(get_current_user)):
    _limit(user, "tr", 40)
    try:
        return await extapi.translate(data.text, data.to)
    except Exception as e:  # noqa: BLE001
        _fail(e)


@router.get("/translate/langs")
def langs():
    return [{"code": k, "name": v} for k, v in extapi.LANGS.items()]


# ── музыка для историй ──

@router.get("/music")
async def music(q: str = "", user: User = Depends(get_current_user)):
    _limit(user, "music", 40)
    try:
        return await extapi.music(q[:100])
    except Exception as e:  # noqa: BLE001
        _fail(e)


@router.post("/music/import")
async def music_import(data: Fetch, user: User = Depends(get_current_user)):
    """Отрывок трека (30 с) — к нам на сервер, чтобы история играла у всех."""
    _limit(user, "import", 30)
    try:
        r = await extapi.download(data.url, max_bytes=6 * 1024 * 1024, kinds=("audio/",))
    except Exception as e:  # noqa: BLE001
        _fail(e)
    return {"url": r["url"], "size": r["size"]}


# ── полезные боты ──

@router.get("/bots")
def builtin_bots(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    from app import builtin_bots as bb
    return bb.list_bots(db)
