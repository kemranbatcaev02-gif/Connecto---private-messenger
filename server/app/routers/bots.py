"""Боты: управление (как @BotFather) и Bot API в стиле Telegram.

Пример на Python:
    import requests
    TOKEN = "..."; API = f"http://193.233.112.115:8000/bot{TOKEN}"
    offset = 0
    while True:
        r = requests.get(f"{API}/getUpdates", params={"offset": offset, "timeout": 25}).json()
        for u in r["result"]:
            offset = u["update_id"] + 1
            m = u["message"]
            requests.post(f"{API}/sendMessage", json={"chat_id": m["chat"]["id"],
                                                     "text": "Ты написал: " + (m["text"] or "")})
"""
import asyncio
import hashlib
import json
import re
import secrets
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.deps import get_db, get_current_user
from app.models.user import User
from app.models.chat import Chat, ChatMember, Message, BotUpdate
from app.core.security import hash_password
from app.privacy import is_premium
from app.realtime import manager
from app.messaging import deliver, bot_message_obj, member_ids

router = APIRouter(prefix="/bots", tags=["bots"])
api_router = APIRouter(tags=["bot-api"])

BOT_USERNAME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9_]{1,28}bot$", re.IGNORECASE)


def _hash(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()


def _new_token(bot: User) -> str:
    secret = secrets.token_urlsafe(30)
    bot.bot_token_hash = _hash(secret)
    return f"{bot.id}:{secret}"


def _commands(bot: User) -> list:
    try:
        return json.loads(bot.bot_commands) if bot.bot_commands else []
    except Exception:
        return []


def _bot_out(bot: User, token: str | None = None) -> dict:
    out = {
        "id": bot.id,
        "username": bot.username,
        "handle": bot.handle,
        "display_name": bot.display_name,
        "bio": bot.bio,
        "avatar_url": bot.avatar_url,
        "commands": _commands(bot),
        "webhook": bot.bot_webhook,
        "created_at": bot.created_at.isoformat() if bot.created_at else None,
    }
    if token:
        out["token"] = token
    return out


def _my_bot(db: Session, bot_id: str, owner: User) -> User:
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True,  # noqa: E712
                                User.bot_owner_id == owner.id).first()
    if bot is None:
        raise HTTPException(status_code=404, detail="Бот не найден")
    return bot


# ── управление ботами ──

@router.get("")
def my_bots(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    rows = (db.query(User).filter(User.bot_owner_id == user.id)
            .order_by(User.created_at.asc()).all())
    return [_bot_out(b) for b in rows]


class BotCreate(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    username: str = Field(min_length=4, max_length=32)


@router.post("", status_code=201)
def create_bot(data: BotCreate, db: Session = Depends(get_db),
               user: User = Depends(get_current_user)):
    uname = data.username.strip().lstrip("@")
    if not BOT_USERNAME_RE.match(uname):
        raise HTTPException(status_code=400,
                            detail="Юзернейм бота: латиница/цифры/_, должен заканчиваться на «bot»")
    limit = 20 if is_premium(user) else 5
    if db.query(User).filter(User.bot_owner_id == user.id).count() >= limit:
        raise HTTPException(status_code=400,
                            detail=f"Можно создать до {limit} ботов"
                                   + ("" if limit == 20 else " (с Premium — до 20)"))
    from sqlalchemy import func
    if (db.query(User).filter(func.lower(User.username) == uname.lower()).first()
            or db.query(User).filter(func.lower(User.handle) == uname.lower()).first()
            or db.query(Chat).filter(func.lower(Chat.handle) == uname.lower()).first()):
        raise HTTPException(status_code=409, detail="Этот юзернейм уже занят")
    bot = User(username=uname, handle=uname,
               email=f"bot-{uuid.uuid4().hex}@bots.connecto.local",
               password_hash=hash_password(secrets.token_hex(16)),
               display_name=data.name.strip(), is_bot=True, bot_owner_id=user.id)
    db.add(bot)
    db.flush()
    token = _new_token(bot)
    db.commit()
    db.refresh(bot)
    return _bot_out(bot, token)


class BotEdit(BaseModel):
    display_name: str | None = Field(default=None, max_length=64)
    bio: str | None = Field(default=None, max_length=300)
    avatar_url: str | None = None
    commands: list[dict] | None = None


@router.patch("/{bot_id}")
def edit_bot(bot_id: str, data: BotEdit, db: Session = Depends(get_db),
             user: User = Depends(get_current_user)):
    bot = _my_bot(db, bot_id, user)
    if data.display_name is not None and data.display_name.strip():
        bot.display_name = data.display_name.strip()
    if data.bio is not None:
        bot.bio = data.bio.strip() or None
    if data.avatar_url is not None:
        bot.avatar_url = data.avatar_url or None
    if data.commands is not None:
        bot.bot_commands = json.dumps(_clean_commands(data.commands), ensure_ascii=False)
    db.commit()
    return _bot_out(bot)


def _clean_commands(cmds: list) -> list:
    out = []
    for c in cmds[:50]:
        if not isinstance(c, dict):
            continue
        name = str(c.get("command", "")).strip().lstrip("/").lower()[:32]
        desc = str(c.get("description", "")).strip()[:120]
        if re.match(r"^[a-z0-9_]{1,32}$", name):
            out.append({"command": name, "description": desc})
    return out


@router.post("/{bot_id}/token")
def regenerate_token(bot_id: str, db: Session = Depends(get_db),
                     user: User = Depends(get_current_user)):
    bot = _my_bot(db, bot_id, user)
    token = _new_token(bot)
    db.commit()
    return _bot_out(bot, token)


@router.delete("/{bot_id}", status_code=204)
def delete_bot(bot_id: str, db: Session = Depends(get_db),
               user: User = Depends(get_current_user)):
    bot = _my_bot(db, bot_id, user)
    from app.routers.users import delete_user_everywhere
    delete_user_everywhere(db, bot.id)
    db.commit()


# ── Bot API ──

def _err(code: int, desc: str) -> JSONResponse:
    return JSONResponse(status_code=code,
                        content={"ok": False, "error_code": code, "description": desc})


def _ok(result) -> dict:
    return {"ok": True, "result": result}


def _bot_by_token(db: Session, token: str) -> User | None:
    if ":" not in token:
        return None
    bot_id, secret = token.split(":", 1)
    bot = db.query(User).filter(User.id == bot_id, User.is_bot == True).first()  # noqa: E712
    if bot is None or not bot.bot_token_hash or bot.bot_owner_id is None:
        return None
    if not secrets.compare_digest(bot.bot_token_hash, _hash(secret)):
        return None
    return bot


async def _params(request: Request) -> dict:
    p = dict(request.query_params)
    if request.method == "POST":
        try:
            body = await request.json()
            if isinstance(body, dict):
                p.update(body)
        except Exception:
            try:
                form = await request.form()
                p.update({k: v for k, v in form.items()})
            except Exception:
                pass
    return p


@api_router.api_route("/bot{token}/{method}", methods=["GET", "POST"])
async def bot_api(token: str, method: str, request: Request, db: Session = Depends(get_db)):
    bot = _bot_by_token(db, token)
    if bot is None:
        return _err(401, "Unauthorized")
    p = await _params(request)
    m = method.lower()
    try:
        if m == "getme":
            return _ok({"id": bot.id, "is_bot": True, "first_name": bot.display_name,
                        "username": bot.handle or bot.username, "can_join_groups": True})
        if m == "getupdates":
            return await _get_updates(db, bot, p)
        if m in ("sendmessage", "sendphoto", "senddocument", "sendvideo"):
            return await _send(db, bot, p, m)
        if m == "editmessagetext":
            return await _edit(db, bot, p)
        if m == "deletemessage":
            return await _delete(db, bot, p)
        if m == "sendchataction":
            chat = _bot_chat(db, bot, p)
            await manager.send_to_users(
                [u for u in member_ids(db, chat.id) if u != bot.id],
                {"type": "typing", "chat_id": chat.id, "user_id": bot.id,
                 "name": bot.display_name, "state": "typing"})
            return _ok(True)
        if m == "setwebhook":
            url = str(p.get("url") or "").strip()
            if url and not url.startswith(("http://", "https://")):
                return _err(400, "Bad Request: invalid webhook URL")
            bot.bot_webhook = url or None
            db.commit()
            return _ok(True)
        if m == "deletewebhook":
            bot.bot_webhook = None
            db.commit()
            return _ok(True)
        if m == "getwebhookinfo":
            pending = db.query(BotUpdate).filter(BotUpdate.bot_id == bot.id).count()
            return _ok({"url": bot.bot_webhook or "", "pending_update_count": pending})
        if m == "setmycommands":
            cmds = p.get("commands") or []
            if isinstance(cmds, str):
                cmds = json.loads(cmds)
            bot.bot_commands = json.dumps(_clean_commands(cmds), ensure_ascii=False)
            db.commit()
            return _ok(True)
        if m == "getmycommands":
            return _ok(_commands(bot))
        if m == "getchat":
            chat = _bot_chat(db, bot, p)
            return _ok({"id": chat.id, "type": {"direct": "private"}.get(chat.type, chat.type),
                        "title": chat.title, "description": chat.description})
        return _err(404, f"Not Found: method {method} not found")
    except HTTPException as e:
        return _err(e.status_code, f"Bad Request: {e.detail}")


def _bot_chat(db: Session, bot: User, p: dict) -> Chat:
    chat_id = str(p.get("chat_id") or "")
    chat = db.query(Chat).filter(Chat.id == chat_id).first()
    if chat is None:
        raise HTTPException(status_code=400, detail="chat not found")
    if db.query(ChatMember).filter(ChatMember.chat_id == chat.id,
                                   ChatMember.user_id == bot.id).first() is None:
        raise HTTPException(status_code=403, detail="bot is not a member of the chat")
    return chat


async def _get_updates(db: Session, bot: User, p: dict):
    offset = int(p.get("offset") or 0)
    limit = max(1, min(int(p.get("limit") or 100), 100))
    timeout = max(0, min(int(p.get("timeout") or 0), 25))
    if offset:
        db.query(BotUpdate).filter(BotUpdate.bot_id == bot.id, BotUpdate.id < offset).delete()
        db.commit()
    waited = 0
    while True:
        rows = (db.query(BotUpdate).filter(BotUpdate.bot_id == bot.id,
                                           BotUpdate.id >= offset)
                .order_by(BotUpdate.id.asc()).limit(limit).all())
        result = [json.loads(r.payload) for r in rows]
        db.rollback()   # не держим транзакцию SQLite, пока ждём
        if result or waited >= timeout:
            return _ok(result)
        await asyncio.sleep(1)
        waited += 1


async def _send(db: Session, bot: User, p: dict, method: str):
    from app.routers.chats import check_can_send
    chat = _bot_chat(db, bot, p)
    kind = {"sendmessage": "text", "sendphoto": "image", "senddocument": "file",
            "sendvideo": "video"}[method]
    check_can_send(db, chat, bot, kind)
    text = str(p.get("text") if kind == "text" else (p.get("caption") or ""))
    media = None
    if kind != "text":
        media = str(p.get({"image": "photo", "file": "document", "video": "video"}[kind]) or "")
        if not media:
            raise HTTPException(status_code=400, detail="media url is required")
    elif not text.strip():
        raise HTTPException(status_code=400, detail="message text is empty")
    msg = Message(chat_id=chat.id, sender_id=bot.id, kind=kind, text=text[:4000],
                  media_url=media, file_name=p.get("file_name"),
                  reply_to_id=p.get("reply_to_message_id"))
    db.add(msg)
    db.commit()
    db.refresh(msg)
    await deliver(db, chat, msg, bot)
    return _ok(bot_message_obj(chat, msg, bot))


async def _edit(db: Session, bot: User, p: dict):
    chat = _bot_chat(db, bot, p)
    msg = db.query(Message).filter(Message.id == str(p.get("message_id") or ""),
                                   Message.chat_id == chat.id).first()
    if msg is None or msg.sender_id != bot.id:
        raise HTTPException(status_code=400, detail="message can't be edited")
    text = str(p.get("text") or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="message text is empty")
    msg.text = text[:4000]
    msg.edited = True
    db.commit()
    await manager.send_to_users(member_ids(db, chat.id), {
        "type": "edited", "chat_id": chat.id, "id": msg.id, "text": msg.text, "edited": True})
    return _ok(bot_message_obj(chat, msg, bot))


async def _delete(db: Session, bot: User, p: dict):
    chat = _bot_chat(db, bot, p)
    msg = db.query(Message).filter(Message.id == str(p.get("message_id") or ""),
                                   Message.chat_id == chat.id).first()
    if msg is None:
        return _ok(True)
    role = (db.query(ChatMember).filter(ChatMember.chat_id == chat.id,
                                        ChatMember.user_id == bot.id).first().role)
    if msg.sender_id != bot.id and role not in ("owner", "admin"):
        raise HTTPException(status_code=400, detail="message can't be deleted")
    db.delete(msg)
    db.commit()
    await manager.send_to_users(member_ids(db, chat.id),
                                {"type": "msg_deleted", "chat_id": chat.id, "id": msg.id})
    return _ok(True)
