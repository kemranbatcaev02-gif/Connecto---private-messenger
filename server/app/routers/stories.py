"""Истории (как в Telegram): кружки над чатами, просмотры, реакции, публикации в профиле.

Без Premium — 2 истории за 7 дней и срок 24 часа.
С Premium — без ограничений (до 50 в день), срок 6/12/24/48 часов, режим инкогнито.
"""
import json
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.deps import get_current_user, get_db
from app.models.user import User
from app.models.chat import Chat, ChatMember
from app.models.social import Story, StoryView
from app.privacy import allowed, is_blocked, is_contact, is_premium, as_utc
from app.realtime import manager

router = APIRouter(tags=["stories"])

FREE_PER_WEEK = 2
PREMIUM_PER_DAY = 50
FREE_HOURS = {24}
PREMIUM_HOURS = {6, 12, 24, 48}
REACTIONS = {"❤️", "🔥", "😂", "😮", "😢", "👍", "🎉", "😍"}


def _now():
    return datetime.now(timezone.utc)


def _mini(u: User | None) -> dict | None:
    if u is None:
        return None
    return {"id": u.id, "display_name": u.display_name or u.username,
            "avatar_url": u.avatar_url, "is_premium": is_premium(u),
            "is_verified": bool(u.is_verified)}


def contact_ids(db: Session, user_id: str) -> list[str]:
    """Собеседники в личных чатах."""
    mine = db.query(ChatMember.chat_id).filter(ChatMember.user_id == user_id)
    rows = (db.query(ChatMember.user_id)
            .join(Chat, Chat.id == ChatMember.chat_id)
            .filter(Chat.type == "direct", Chat.is_system == False,  # noqa: E712
                    ChatMember.chat_id.in_(mine), ChatMember.user_id != user_id)
            .all())
    return list({r[0] for r in rows})


def can_see(db: Session, story: Story, owner: User | None, viewer_id: str) -> bool:
    if owner is None or story.deleted_at is not None:
        return False
    if owner.id == viewer_id:
        return True
    if owner.banned or is_blocked(db, owner.id, viewer_id):
        return False
    if not allowed(db, owner, viewer_id, "stories"):
        return False
    if story.audience == "contacts" and not is_contact(db, owner.id, viewer_id):
        return False
    return True


def is_active(s: Story) -> bool:
    return s.deleted_at is None and as_utc(s.expires_at) > _now()


def story_dict(db: Session, s: Story, viewer_id: str, seen_ids: set | None = None) -> dict:
    mine = s.user_id == viewer_id
    d = {
        "id": s.id,
        "user_id": s.user_id,
        "media_url": s.media_url,
        "kind": s.kind,
        "caption": s.caption or "",
        "audience": s.audience,
        "pinned": bool(s.pinned),
        "active": is_active(s),
        "created_at": as_utc(s.created_at).isoformat() if s.created_at else None,
        "expires_at": as_utc(s.expires_at).isoformat() if s.expires_at else None,
        "overlays": _overlays(s),
        "music_url": s.music_url,
        "music_title": s.music_title,
    }
    if seen_ids is not None:
        d["seen"] = mine or s.id in seen_ids
    if mine:
        views = db.query(StoryView).filter(StoryView.story_id == s.id)
        d["views_count"] = views.count()
        d["reactions_count"] = views.filter(StoryView.reaction.isnot(None)).count()
    else:
        v = (db.query(StoryView).filter(StoryView.story_id == s.id,
                                        StoryView.viewer_id == viewer_id).first())
        d["my_reaction"] = v.reaction if v else None
    return d


def _overlays(s: Story) -> list:
    if not s.overlays:
        return []
    try:
        v = json.loads(s.overlays)
        return v if isinstance(v, list) else []
    except Exception:
        return []


def _seen_set(db: Session, viewer_id: str, story_ids: list[str]) -> set:
    if not story_ids:
        return set()
    return {r[0] for r in db.query(StoryView.story_id)
            .filter(StoryView.viewer_id == viewer_id, StoryView.story_id.in_(story_ids))}


def _get(db: Session, story_id: str) -> Story:
    s = db.query(Story).filter(Story.id == story_id).first()
    if s is None or s.deleted_at is not None:
        raise HTTPException(status_code=404, detail="История удалена")
    return s


def _visible_or_404(db: Session, story_id: str, me: User) -> tuple[Story, User]:
    s = _get(db, story_id)
    owner = db.query(User).filter(User.id == s.user_id).first()
    if not can_see(db, s, owner, me.id):
        raise HTTPException(status_code=404, detail="История недоступна")
    return s, owner


def limits(db: Session, user: User) -> dict:
    now = _now()
    if is_premium(user):
        used = (db.query(Story).filter(Story.user_id == user.id,
                                       Story.created_at > now - timedelta(days=1)).count())
        return {"premium": True, "used": used, "limit": PREMIUM_PER_DAY, "period": "day",
                "left": max(0, PREMIUM_PER_DAY - used), "hours": sorted(PREMIUM_HOURS),
                "next_at": None}
    week = (db.query(Story).filter(Story.user_id == user.id,
                                   Story.created_at > now - timedelta(days=7))
            .order_by(Story.created_at.asc()).all())
    left = max(0, FREE_PER_WEEK - len(week))
    next_at = None
    if left == 0 and week:
        next_at = (as_utc(week[0].created_at) + timedelta(days=7)).isoformat()
    return {"premium": False, "used": len(week), "limit": FREE_PER_WEEK, "period": "week",
            "left": left, "hours": sorted(FREE_HOURS), "next_at": next_at}


async def _notify(db: Session, user: User, payload: dict) -> None:
    ids = contact_ids(db, user.id) + [user.id]
    await manager.send_to_users(ids, payload)


# ── лента ──

@router.get("/stories")
def feed(db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    """Кружки над чатами: я + собеседники с активными историями."""
    now = _now()
    owner_ids = [me.id] + contact_ids(db, me.id)
    rows = (db.query(Story)
            .filter(Story.user_id.in_(owner_ids), Story.deleted_at.is_(None),
                    Story.expires_at > now)
            .order_by(Story.created_at.asc()).all())
    seen = _seen_set(db, me.id, [s.id for s in rows])
    users = {u.id: u for u in db.query(User).filter(User.id.in_({s.user_id for s in rows})).all()}
    groups: dict[str, list] = {}
    for s in rows:
        owner = users.get(s.user_id)
        if not can_see(db, s, owner, me.id):
            continue
        groups.setdefault(s.user_id, []).append(story_dict(db, s, me.id, seen))
    out = []
    for oid, items in groups.items():
        out.append({
            "user": _mini(users.get(oid)),
            "is_me": oid == me.id,
            "stories": items,
            "has_unseen": any(not i["seen"] for i in items),
            "latest_at": items[-1]["created_at"],
        })
    # я — первым, дальше непросмотренные, потом просмотренные; внутри «непросмотренных» и «просмотренных» — свежие первыми
    mine = [g for g in out if g["is_me"]]
    unseen = sorted([g for g in out if not g["is_me"] and g["has_unseen"]],
                    key=lambda g: g["latest_at"] or "", reverse=True)
    seen_g = sorted([g for g in out if not g["is_me"] and not g["has_unseen"]],
                    key=lambda g: g["latest_at"] or "", reverse=True)
    return {"groups": mine + unseen + seen_g, "limits": limits(db, me)}


@router.get("/stories/limits")
def my_limits(db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    return limits(db, me)


@router.get("/stories/user/{user_id}")
def user_stories(user_id: str, db: Session = Depends(get_db),
                 me: User = Depends(get_current_user)):
    owner = db.query(User).filter(User.id == user_id).first()
    if owner is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    rows = (db.query(Story).filter(Story.user_id == user_id, Story.deleted_at.is_(None),
                                   Story.expires_at > _now())
            .order_by(Story.created_at.asc()).all())
    rows = [s for s in rows if can_see(db, s, owner, me.id)]
    seen = _seen_set(db, me.id, [s.id for s in rows])
    return {"user": _mini(owner), "stories": [story_dict(db, s, me.id, seen) for s in rows]}


@router.get("/users/{user_id}/posts")
def user_posts(user_id: str, db: Session = Depends(get_db),
               me: User = Depends(get_current_user)):
    """«Публикации» в профиле: закреплённые истории (в том числе истёкшие)."""
    owner = db.query(User).filter(User.id == user_id).first()
    if owner is None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    rows = (db.query(Story).filter(Story.user_id == user_id, Story.pinned == True,  # noqa: E712
                                   Story.deleted_at.is_(None))
            .order_by(Story.created_at.desc()).limit(90).all())
    rows = [s for s in rows if can_see(db, s, owner, me.id)]
    seen = _seen_set(db, me.id, [s.id for s in rows])
    return [story_dict(db, s, me.id, seen) for s in rows]


@router.get("/stories/archive")
def my_archive(db: Session = Depends(get_db), me: User = Depends(get_current_user)):
    """Все мои истории (архив) — можно закрепить старые в профиль."""
    rows = (db.query(Story).filter(Story.user_id == me.id, Story.deleted_at.is_(None))
            .order_by(Story.created_at.desc()).limit(200).all())
    return [story_dict(db, s, me.id, set()) for s in rows]


# ── создание и управление ──

class StoryIn(BaseModel):
    media_url: str = Field(min_length=1, max_length=512)
    kind: str = Field(default="image", pattern=r"^(image|video)$")
    caption: str = Field(default="", max_length=500)
    audience: str = Field(default="all", pattern=r"^(all|contacts)$")
    pinned: bool = False
    hours: int = 24
    overlays: list[dict] = Field(default_factory=list, max_length=30)
    music_url: str | None = Field(default=None, max_length=512)
    music_title: str | None = Field(default=None, max_length=128)


@router.post("/stories", status_code=201)
async def create_story(data: StoryIn, db: Session = Depends(get_db),
                       me: User = Depends(get_current_user)):
    if me.is_bot:
        raise HTTPException(status_code=403, detail="Боты не публикуют истории")
    lim = limits(db, me)
    if lim["left"] <= 0:
        if lim["premium"]:
            raise HTTPException(status_code=429, detail="Лимит историй на сегодня исчерпан")
        raise HTTPException(status_code=403,
                            detail="Без Premium — 2 истории в неделю. "
                                   "С Connecto Premium истории без ограничений")
    hours = data.hours if data.hours in (PREMIUM_HOURS if lim["premium"] else FREE_HOURS) else 24
    if data.hours != hours and not lim["premium"]:
        raise HTTPException(status_code=403,
                            detail="Выбирать срок истории можно с Connecto Premium")
    now = _now()
    overlays = json.dumps(data.overlays, ensure_ascii=False) if data.overlays else None
    if overlays and len(overlays) > 20000:
        raise HTTPException(status_code=400, detail="Слишком много элементов на истории")
    s = Story(user_id=me.id, media_url=data.media_url, kind=data.kind,
              caption=data.caption.strip(), audience=data.audience, pinned=data.pinned,
              created_at=now, expires_at=now + timedelta(hours=hours),
              overlays=overlays, music_url=data.music_url or None,
              music_title=(data.music_title or "").strip()[:128] or None)
    db.add(s)
    db.commit()
    db.refresh(s)
    await _notify(db, me, {"type": "story_new", "user_id": me.id, "story_id": s.id})
    out = story_dict(db, s, me.id, set())
    out["limits"] = limits(db, me)
    return out


@router.delete("/stories/{story_id}", status_code=204)
async def delete_story(story_id: str, db: Session = Depends(get_db),
                       me: User = Depends(get_current_user)):
    s = _get(db, story_id)
    if s.user_id != me.id:
        raise HTTPException(status_code=403, detail="Это не твоя история")
    s.deleted_at = _now()
    db.commit()
    await _notify(db, me, {"type": "story_deleted", "user_id": me.id, "story_id": s.id})


class PinIn(BaseModel):
    pinned: bool = True


@router.put("/stories/{story_id}/pin")
def pin_story(story_id: str, data: PinIn, db: Session = Depends(get_db),
              me: User = Depends(get_current_user)):
    s = _get(db, story_id)
    if s.user_id != me.id:
        raise HTTPException(status_code=403, detail="Это не твоя история")
    s.pinned = data.pinned
    db.commit()
    return story_dict(db, s, me.id, set())


# ── просмотры и реакции ──

@router.post("/stories/{story_id}/view")
def view_story(story_id: str, stealth: bool = False, db: Session = Depends(get_db),
               me: User = Depends(get_current_user)):
    s, _owner = _visible_or_404(db, story_id, me)
    if s.user_id == me.id:
        return {"ok": True}
    if stealth and is_premium(me):
        return {"ok": True, "stealth": True}   # инкогнито: автор не увидит просмотр
    if not (db.query(StoryView).filter(StoryView.story_id == s.id,
                                       StoryView.viewer_id == me.id).first()):
        db.add(StoryView(story_id=s.id, viewer_id=me.id))
        db.commit()
    return {"ok": True}


class ReactIn(BaseModel):
    emoji: str | None = Field(default=None, max_length=16)


@router.post("/stories/{story_id}/react")
async def react_story(story_id: str, data: ReactIn, db: Session = Depends(get_db),
                      me: User = Depends(get_current_user)):
    s, owner = _visible_or_404(db, story_id, me)
    if s.user_id == me.id:
        raise HTTPException(status_code=400, detail="Нельзя реагировать на свою историю")
    emoji = (data.emoji or "").strip() or None
    if emoji and emoji not in REACTIONS:
        raise HTTPException(status_code=400, detail="Такой реакции нет")
    v = (db.query(StoryView).filter(StoryView.story_id == s.id,
                                    StoryView.viewer_id == me.id).first())
    if v is None:
        v = StoryView(story_id=s.id, viewer_id=me.id)
        db.add(v)
    v.reaction = emoji
    db.commit()
    if emoji:
        await manager.send_to_users([s.user_id], {
            "type": "story_reaction", "story_id": s.id, "emoji": emoji,
            "user_id": me.id, "name": me.display_name or me.username})
    return {"ok": True, "reaction": emoji}


@router.get("/stories/{story_id}/viewers")
def story_viewers(story_id: str, db: Session = Depends(get_db),
                  me: User = Depends(get_current_user)):
    s = _get(db, story_id)
    if s.user_id != me.id:
        raise HTTPException(status_code=403, detail="Просмотры видит только автор")
    rows = (db.query(StoryView).filter(StoryView.story_id == s.id)
            .order_by(StoryView.reaction.is_(None), StoryView.created_at.desc()).limit(500).all())
    users = {u.id: u for u in db.query(User).filter(User.id.in_([r.viewer_id for r in rows])).all()}
    return [{"user": _mini(users.get(r.viewer_id)), "reaction": r.reaction,
             "viewed_at": as_utc(r.created_at).isoformat() if r.created_at else None}
            for r in rows if users.get(r.viewer_id) is not None]


def story_for_reply(db: Session, story_id: str, me: User) -> dict:
    """Для ответа на историю в личке: мини-превью истории."""
    s, owner = _visible_or_404(db, story_id, me)
    return {"story": {"id": s.id, "media_url": s.media_url, "kind": s.kind,
                      "owner_id": s.user_id,
                      "owner_name": (owner.display_name or owner.username) if owner else ""}}


# ── погода для стикера ──

_WEATHER_CODES = [
    ((0,), "☀️", "Ясно"), ((1, 2), "🌤", "Малооблачно"), ((3,), "☁️", "Облачно"),
    ((45, 48), "🌫", "Туман"), ((51, 53, 55, 56, 57), "🌦", "Морось"),
    ((61, 63, 65, 66, 67, 80, 81, 82), "🌧", "Дождь"), ((71, 73, 75, 77, 85, 86), "🌨", "Снег"),
    ((95, 96, 99), "⛈", "Гроза"),
]
_weather_cache: dict = {}


def _fetch_json(url: str) -> dict:
    import urllib.request
    req = urllib.request.Request(url, headers={"User-Agent": "Connecto/1.0 (messenger)"})
    with urllib.request.urlopen(req, timeout=6) as r:
        return json.loads(r.read().decode("utf-8"))


@router.get("/stories/weather")
def weather(request: Request, lat: float | None = None, lon: float | None = None,
            me: User = Depends(get_current_user)):
    """Текущая погода (Open-Meteo, без ключа). Без координат — по IP."""
    import time
    city = ""
    if lat is None or lon is None:
        from app.routers.auth import _client_ip
        ip = _client_ip(request)
        try:
            d = _fetch_json(f"http://ip-api.com/json/{ip}?fields=status,city,lat,lon&lang=ru")
            if d.get("status") == "success":
                lat, lon, city = d.get("lat"), d.get("lon"), d.get("city") or ""
        except Exception:
            pass
    if lat is None or lon is None:
        raise HTTPException(status_code=503, detail="Не удалось определить место")
    key = (round(lat, 1), round(lon, 1))
    hit = _weather_cache.get(key)
    if hit and time.time() - hit[0] < 600:
        out = dict(hit[1])
    else:
        try:
            d = _fetch_json("https://api.open-meteo.com/v1/forecast?latitude="
                            f"{lat}&longitude={lon}&current=temperature_2m,weather_code")
            cur = d.get("current") or {}
            code = int(cur.get("weather_code", 0))
            emoji, text = "🌡", "Погода"
            for codes, e, t in _WEATHER_CODES:
                if code in codes:
                    emoji, text = e, t
                    break
            out = {"temp": round(float(cur.get("temperature_2m", 0))), "emoji": emoji,
                   "text": text, "code": code}
            _weather_cache[key] = (time.time(), out)
            out = dict(out)
        except Exception:
            raise HTTPException(status_code=503, detail="Погода сейчас недоступна")
    if not city:
        try:
            d = _fetch_json("https://nominatim.openstreetmap.org/reverse?format=json&zoom=10"
                            f"&accept-language=ru&lat={lat}&lon={lon}")
            a = d.get("address") or {}
            city = a.get("city") or a.get("town") or a.get("village") or a.get("state") or ""
        except Exception:
            city = ""
    out["city"] = city
    return out
