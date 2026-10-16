import asyncio
import html
import os
import secrets
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from app.database import Base, engine, SessionLocal
from app.models import user as _user_model      # noqa: F401
from app.models import chat as _chat_model       # noqa: F401
from app.models import social as _social_model   # noqa: F401
from app.models.chat import Chat, ChatMember
from app.routers import auth, users, chats, upload, admin, bots, premium, stories, economy, keys
from app.routers import ext, shop
from app.realtime import manager
from app import calls

APP_VERSION = "0.12.0"
WS_IDLE = 35


# Мягкая миграция: добавляет недостающие колонки, ничего не удаляя.
MIGRATIONS = {
    "users": {
        "last_name": "VARCHAR(64)",
        "bio": "VARCHAR(300)",
        "phone": "VARCHAR(32)",
        "birthday": "VARCHAR(20)",
        "handle": "VARCHAR(32)",
        "lastseen_privacy": "VARCHAR(10) DEFAULT 'all'",
        "banned": "INTEGER DEFAULT 0",
        "privacy": "TEXT",
        "read_receipts": "INTEGER DEFAULT 1",
        "notify": "TEXT",
        "cloud_password_hash": "VARCHAR(255)",
        "cloud_password_hint": "VARCHAR(64)",
        "premium_until": "DATETIME",
        "is_bot": "INTEGER DEFAULT 0",
        "is_verified": "INTEGER DEFAULT 0",
        "bot_owner_id": "VARCHAR(36)",
        "bot_token_hash": "VARCHAR(128)",
        "bot_webhook": "VARCHAR(512)",
        "bot_commands": "TEXT",
        "last_seen": "DATETIME",
        "cover_url": "VARCHAR(512)",
        "cover_kind": "VARCHAR(10)",
        "emoji_status": "VARCHAR(16)",
        "coins": "INTEGER DEFAULT 0",
        "daily_streak": "INTEGER DEFAULT 0",
        "daily_last": "VARCHAR(10)",
        "avatar_ring": "VARCHAR(16)",
        "cover_item": "VARCHAR(48)",
        "avatar_frame": "VARCHAR(48)",
        "profile_fx": "VARCHAR(48)",
    },
    "stories": {
        "overlays": "TEXT",
        "music_url": "VARCHAR(512)",
        "music_title": "VARCHAR(128)",
    },
    "gift_defs": {
        "bg": "VARCHAR(24)",
        "fx": "VARCHAR(24)",
        "anim": "VARCHAR(16)",
        "symbol": "VARCHAR(16)",
    },
    "user_gifts": {
        "pinned": "INTEGER DEFAULT 0",
        "upgraded": "INTEGER DEFAULT 0",
        "backdrop": "VARCHAR(24)",
        "pattern": "VARCHAR(24)",
        "unique_no": "INTEGER",
        "upgrade_cost": "INTEGER DEFAULT 0",
    },
    "messages": {
        "kind": "VARCHAR(16) DEFAULT 'text'",
        "media_url": "VARCHAR(512)",
        "file_name": "VARCHAR(255)",
        "reply_to_id": "VARCHAR(36)",
        "forwarded_from": "VARCHAR(36)",
        "edited": "INTEGER DEFAULT 0",
        "pinned": "INTEGER DEFAULT 0",
        "effect": "VARCHAR(16)",
        "silent": "INTEGER DEFAULT 0",
        "open_at": "DATETIME",
        "expires_at": "DATETIME",
        "extra": "TEXT",
        "enc": "TEXT",
    },
    "chats": {
        "description": "VARCHAR(500)",
        "avatar_url": "VARCHAR(512)",
        "handle": "VARCHAR(32)",
        "invite_code": "VARCHAR(32)",
        "owner_id": "VARCHAR(36)",
        "members_can_send": "INTEGER DEFAULT 1",
        "members_can_add": "INTEGER DEFAULT 1",
        "is_system": "INTEGER DEFAULT 0",
        "is_verified": "INTEGER DEFAULT 0",
        "ttl_seconds": "INTEGER DEFAULT 0",
    },
    "promo_codes": {
        "coins": "INTEGER DEFAULT 0",
    },
    "chat_members": {
        "muted_until": "INTEGER DEFAULT 0",
        "cleared_at": "DATETIME",
    },
}


def _ensure_columns():
    with engine.begin() as conn:
        if engine.dialect.name != "sqlite":
            return
        for table, cols in MIGRATIONS.items():
            existing = [r[1] for r in conn.execute(text(f"PRAGMA table_info({table})"))]
            if not existing:
                continue
            for name, typ in cols.items():
                if name not in existing:
                    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {typ}"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_messages_chat_created ON messages (chat_id, created_at)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_chat_members_chat_user ON chat_members (chat_id, user_id)"))


def _backfill():
    """Старые группы/каналы: владелец и ссылка-приглашение."""
    db = SessionLocal()
    try:
        for chat in db.query(Chat).filter(Chat.type.in_(("group", "channel"))).all():
            changed = False
            if not chat.invite_code:
                chat.invite_code = secrets.token_urlsafe(8)
                changed = True
            if not chat.owner_id:
                owner = (db.query(ChatMember).filter(ChatMember.chat_id == chat.id,
                                                     ChatMember.role == "owner").first()
                         or db.query(ChatMember).filter(ChatMember.chat_id == chat.id)
                         .order_by(ChatMember.joined_at.asc()).first())
                if owner:
                    owner.role = "owner"
                    chat.owner_id = owner.user_id
                    changed = True
            if changed:
                db.commit()
        from app import sysbot
        sysbot.get_bot(db)
        sysbot.backfill_support(db)
    finally:
        db.close()


async def _expire_loop():
    """Раз в 15 секунд удаляем исчезнувшие сообщения и сообщаем участникам."""
    import asyncio
    from app.messaging import purge_expired
    while True:
        try:
            await asyncio.sleep(15)
            db = SessionLocal()
            try:
                await purge_expired(db)
            finally:
                db.close()
        except asyncio.CancelledError:
            break
        except Exception:
            pass


@asynccontextmanager
async def lifespan(app: FastAPI):
    import asyncio
    Base.metadata.create_all(bind=engine)
    _ensure_columns()
    _backfill()
    # подарки живут в базе: при первом запуске переносим встроенный набор
    try:
        from app.routers.economy import seed_gifts
        db = SessionLocal()
        try:
            seed_gifts(db)
        finally:
            db.close()
    except Exception as e:  # сервер должен подняться даже при ошибке
        print("seed_gifts:", e)
    try:
        from app import builtin_bots
        db = SessionLocal()
        try:
            builtin_bots.ensure_bots(db)
        finally:
            db.close()
    except Exception:
        pass
    task = asyncio.create_task(_expire_loop())
    yield
    task.cancel()


app = FastAPI(title="Connecto API", version=APP_VERSION, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def _safe_media(request, call_next):
    """Загруженные файлы нельзя «запустить» как страницу: веб-версия живёт на том же
    адресе, и HTML/SVG из чата иначе смог бы прочитать токен входа."""
    resp = await call_next(request)
    if request.url.path.startswith(("/media/", "/download/")):
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["Content-Security-Policy"] = "sandbox; default-src 'none'; img-src 'self' data:; media-src 'self'; style-src 'unsafe-inline'"
    if request.url.path.startswith("/media/"):
        # Кэширование медиа-файлов, обложек и товаров магазина на 1 год
        resp.headers["Cache-Control"] = "public, max-age=31536000, immutable"
        if request.query_params.get("download"):
            name = request.query_params.get("name")
            if name:
                from urllib.parse import quote
                q_name = quote(name)
                resp.headers["Content-Disposition"] = f'attachment; filename="{q_name}"; filename*=UTF-8\'\'{q_name}'
            else:
                resp.headers["Content-Disposition"] = "attachment"
    return resp


app.include_router(auth.router)
app.include_router(users.router)
app.include_router(chats.router)
app.include_router(chats.join_router)
app.include_router(upload.router)
app.include_router(admin.router)
app.include_router(premium.router)
app.include_router(stories.router)
app.include_router(economy.router)
app.include_router(economy.gifts_router)
# Оплата RollyPay — код готов, пока выключен (см. app/routers/rollypay.py):
# from app.routers import rollypay
# app.include_router(rollypay.router)
app.include_router(bots.router)
app.include_router(keys.router)
app.include_router(calls.router)
app.include_router(bots.api_router)
app.include_router(ext.router)
# app.include_router(shop.router)
# app.include_router(shop.admin_router)

os.makedirs('media', exist_ok=True)
app.mount('/media', StaticFiles(directory='media'), name='media')
os.makedirs('downloads', exist_ok=True)
app.mount('/download', StaticFiles(directory='downloads'), name='download')


@app.get("/")
def root():
    return {"app": "Connecto API", "status": "ok", "version": APP_VERSION}


# Версия приложения для проверки обновлений (правь app_version.json рядом с сервером).
_APP_VERSION_DEFAULT = {
    "build": 3,
    "version": "0.5",
    "url_direct": "http://193.233.112.115:8000/download/app-release.apk",
    "url_telegram": "",
    "notes": "Новая версия Connecto",
}
APP_VERSION_FILE = "app_version.json"


@app.get("/app_version")
def app_version():
    import json
    try:
        with open(APP_VERSION_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        # для Windows в том же файле блок "windows": {build, version, url, notes}
        return {**_APP_VERSION_DEFAULT, **data}
    except Exception:
        return _APP_VERSION_DEFAULT


@app.get("/j/{code}", response_class=HTMLResponse)
def invite_page(code: str):
    """Ссылка-приглашение, открытая в браузере: подсказка, как вступить."""
    db = SessionLocal()
    try:
        chat = db.query(Chat).filter(Chat.invite_code == code).first()
        count = db.query(ChatMember).filter(ChatMember.chat_id == chat.id).count() if chat else 0
    finally:
        db.close()
    if chat is None:
        title, sub = "Ссылка недействительна", "Попросите новую ссылку-приглашение."
    else:
        kind = "Канал" if chat.type == "channel" else "Группа"
        who = "подписчиков" if chat.type == "channel" else "участников"
        title = html.escape(chat.title or kind)
        sub = f"{kind} · {count} {who}"
    return f"""<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} — Connecto</title>
<style>body{{margin:0;min-height:100vh;display:grid;place-items:center;background:#0a0b0f;
color:#f5f6f8;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif}}
.c{{max-width:360px;margin:24px;padding:32px 28px;border-radius:26px;background:#15171e;text-align:center}}
.l{{width:84px;height:84px;margin:0 auto 18px;border-radius:26px;display:grid;place-items:center;
font-size:40px;font-weight:800;background:linear-gradient(135deg,#7c6cff,#a79dff)}}
h1{{font-size:22px;margin:0 0 6px}}p{{color:#8a8f9c;margin:0 0 18px;line-height:1.45}}
code{{display:block;padding:12px;border-radius:14px;background:#0a0b0f;color:#a79dff;word-break:break-all}}</style>
</head><body><div class="c"><div class="l">C</div><h1>{title}</h1><p>{sub}</p>
<p>Открой Connecto → поиск и вставь эту ссылку, чтобы вступить.</p>
<code>{html.escape(code)}</code></div></body></html>"""


async def _broadcast_user_status(user_id: str, is_online: bool, last_seen_iso: str | None = None) -> None:
    """Оповещаем активных собеседников о смене онлайн/офлайн статуса."""
    db = SessionLocal()
    try:
        user_chats = [r[0] for r in db.query(ChatMember.chat_id).filter(ChatMember.user_id == user_id).all()]
        if not user_chats:
            return
        peer_ids = list({
            r[0] for r in db.query(ChatMember.user_id)
            .filter(ChatMember.chat_id.in_(user_chats), ChatMember.user_id != user_id)
            .all()
        })
        online_peers = [pid for pid in peer_ids if manager.is_online(pid)]
    except Exception:
        online_peers = []
    finally:
        db.close()
    if online_peers:
        await manager.send_to_users(online_peers, {
            "type": "user_status",
            "user_id": user_id,
            "online": is_online,
            "last_seen": last_seen_iso,
        })


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket, token: str = Query(...)):
    from app.deps import user_from_token
    db = SessionLocal()
    try:
        try:
            user = user_from_token(db, token)
        except Exception:
            await websocket.close(code=1008)
            return
        user_id = user.id
        user_name = user.display_name or user.username
    finally:
        db.close()
    was_online = manager.is_online(user_id)
    await manager.connect(user_id, websocket)
    if not was_online:
        asyncio.create_task(_broadcast_user_status(user_id, True, None))
    try:
        await calls.on_connect(user_id, websocket)
        while True:
            # клиент пингует каждые 20 с; тишина дольше — соединение мёртвое (телефон уснул)
            data = await asyncio.wait_for(websocket.receive_json(), timeout=WS_IDLE)
            if not isinstance(data, dict):
                continue
            if data.get("type") == "typing":
                chat_id = data.get("chat_id")
                if not chat_id:
                    continue
                db = SessionLocal()
                try:
                    chat = db.query(Chat).filter(Chat.id == chat_id).first()
                    if chat is None or chat.type == "channel":
                        continue
                    rows = db.query(ChatMember).filter(ChatMember.chat_id == chat_id).all()
                    ids = [m.user_id for m in rows]
                    if user_id not in ids:
                        continue
                    who_id, who_name = user_id, user_name
                    if chat.is_system and any(m.user_id == user_id and m.role == "support"
                                              for m in rows):
                        # админ печатает в обращении — человек видит «Connecto печатает…»
                        from app import sysbot
                        who_id, who_name = sysbot.get_bot(db).id, "Connecto"
                finally:
                    db.close()
                await manager.send_to_users([i for i in ids if i != user_id], {
                    "type": "typing", "chat_id": chat_id, "user_id": who_id,
                    "name": who_name, "state": data.get("state", "typing"),
                })
            elif str(data.get("type", "")).startswith("call."):
                try:
                    await calls.handle(user_id, data)
                except Exception:
                    pass
            elif data.get("type") == "ping":
                await websocket.send_json({"type": "pong"})
    except (WebSocketDisconnect, asyncio.TimeoutError):
        pass
    except Exception:
        pass
    finally:
        manager.disconnect(user_id, websocket)
        if not manager.is_online(user_id):
            last_seen_iso = _touch_last_seen(user_id)
            try:
                await _broadcast_user_status(user_id, False, last_seen_iso)
            except Exception:
                pass
            try:
                await calls.on_disconnect(user_id)
            except Exception:
                pass


def _touch_last_seen(user_id: str) -> str | None:
    """Запоминаем момент, когда пользователь ушёл офлайн, и возвращаем ISO."""
    from datetime import datetime, timezone
    from app.models.user import User
    db = SessionLocal()
    iso = None
    try:
        u = db.query(User).filter(User.id == user_id).first()
        if u:
            now = datetime.now(timezone.utc)
            u.last_seen = now
            db.commit()
            iso = now.isoformat()
    except Exception:
        pass
    finally:
        db.close()
    return iso
