"""Звонки 1-на-1 (голос и видео).

Сервер только передаёт «рукопожатие» WebRTC (SDP и ICE-кандидаты) через
WebSocket. Сам звук и видео идут напрямую между телефонами (P2P) или через
наш TURN-сервер, и в обоих случаях зашифрованы DTLS-SRTP — сервер их не видит.

Протокол (type в WebSocket-сообщении):
  клиент → сервер: call.invite, call.ringing, call.accept, call.decline,
                   call.end, call.ice, call.sdp, call.restart, call.sync
  сервер → клиент: call.incoming, call.sent, call.ringing, call.accepted, call.taken,
                   call.ended, call.ice, call.sdp, call.restart, call.error
В каждом сообщении клиент передаёт device — так звонок не путается между
несколькими телефонами одного аккаунта.
После звонка в чате появляется сообщение kind="call" (история звонков).
"""
import asyncio
import base64
import hashlib
import hmac
import json
import re
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from app.config import settings
from app.database import SessionLocal
from app.deps import get_db, get_current_user
from app.models.chat import Chat, ChatMember, Message, PushToken
from app.models.user import User
from app.privacy import allowed, is_blocked, public_user
from app.realtime import manager

RING_TIMEOUT = 45          # сколько звонит, пока не станет «пропущенным»
CALLER_GONE_GRACE = 12     # звонящий пропал из сети во время гудков
ABANDON_GRACE = 90         # оба пропали во время разговора
MAX_SDP = 30000
MAX_ICE = 60
CALL_ID_RE = re.compile(r"^[A-Za-z0-9_-]{8,64}$")

router = APIRouter(prefix="/calls", tags=["calls"])


@dataclass
class Call:
    id: str
    chat_id: str
    caller_id: str
    callee_id: str
    video: bool
    sdp: str
    created: float
    state: str = "ringing"            # ringing | active
    accepted_at: float | None = None
    caller_ice: list = field(default_factory=list)
    timer: asyncio.Task | None = None
    caller_dev: str = ""
    callee_dev: str = ""
    answer: str = ""
    rang: bool = False              # телефон собеседника подтвердил, что звонит

    def other(self, uid: str) -> str:
        return self.callee_id if uid == self.caller_id else self.caller_id


CALLS: dict[str, Call] = {}
BY_USER: dict[str, str] = {}          # user_id → call_id (кто сейчас в звонке)
_INVITES: dict[str, deque] = {}       # защита от спама звонками
_PAIRS: dict[tuple, deque] = {}       # … и отдельно — одному и тому же человеку
SILENT_PUSH_AFTER = 4                  # сокет «в сети», но телефон спит — шлём пуш


class CallError(Exception):
    def __init__(self, reason: str, message: str):
        super().__init__(message)
        self.reason = reason
        self.message = message


# ─────────────────────────────── ICE / TURN ───────────────────────────────

def turn_enabled() -> bool:
    return bool(settings.turn_secret)


def ice_servers(user_id: str) -> list[dict]:
    """STUN всегда; TURN — если настроен (временный логин по общему секрету,
    как в coturn с use-auth-secret)."""
    servers: list[dict] = []
    if turn_enabled():
        host, port = settings.turn_host, settings.turn_port
        expires = int(time.time()) + 24 * 3600
        username = f"{expires}:{user_id}"
        digest = hmac.new(settings.turn_secret.encode(), username.encode(), hashlib.sha1).digest()
        servers.append({"urls": [f"stun:{host}:{port}"]})
        servers.append({
            "urls": [f"turn:{host}:{port}?transport=udp", f"turn:{host}:{port}?transport=tcp"],
            "username": username,
            "credential": base64.b64encode(digest).decode(),
        })
    servers.append({"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]})
    return servers


def wants_relay(db: Session, me: User, other_id: str) -> bool:
    """Скрыть мой IP от собеседника (настройка «Peer-to-peer»).
    Без TURN-сервера спрятать IP нельзя — тогда звонок идёт как обычно."""
    return turn_enabled() and not allowed(db, me, other_id, "p2p")


# ─────────────────────────────── проверки ───────────────────────────────

def check_call(db: Session, chat_id: str, caller: User) -> tuple[Chat, User]:
    chat = db.query(Chat).filter(Chat.id == chat_id).first()
    rows = db.query(ChatMember).filter(ChatMember.chat_id == chat_id).all() if chat else []
    if chat is None or not any(r.user_id == caller.id for r in rows):
        raise CallError("not_found", "Чат не найден")
    if chat.type != "direct" or chat.is_system:
        raise CallError("unsupported", "Звонки доступны только в личных чатах")
    other_id = next((r.user_id for r in rows if r.user_id != caller.id and r.role != "support"), None)
    peer = db.query(User).filter(User.id == other_id).first() if other_id else None
    if peer is None or peer.banned:
        raise CallError("unavailable", "Этот аккаунт недоступен")
    if peer.is_bot:
        raise CallError("unsupported", "Ботам позвонить нельзя")
    if is_blocked(db, caller.id, peer.id):
        raise CallError("blocked", "Вы заблокировали этого пользователя")
    if is_blocked(db, peer.id, caller.id) or not allowed(db, peer, caller.id, "calls"):
        raise CallError("privacy", "Пользователь ограничил звонки")
    return chat, peer


@router.get("/prepare")
def prepare(chat_id: str = Query(...), db: Session = Depends(get_db),
            user: User = Depends(get_current_user)):
    """Перед звонком: можно ли звонить, ICE-серверы и режим «только через сервер»."""
    try:
        _chat, peer = check_call(db, chat_id, user)
    except CallError as e:
        raise HTTPException(status_code=403, detail=e.message)
    card = public_user(db, peer, user.id)
    return {
        "ok": True,
        "ice_servers": ice_servers(user.id),
        "relay": wants_relay(db, user, peer.id),
        "turn": turn_enabled(),
        "peer": {"id": peer.id, "name": card["display_name"], "avatar_url": card["avatar_url"]},
    }


# ─────────────────────────────── отправка ───────────────────────────────

async def _send(user_id: str, payload: dict) -> None:
    await manager.send_to_users([user_id], payload)


async def _error(user_id: str, call_id: str | None, reason: str, message: str) -> None:
    await _send(user_id, {"type": "call.error", "call_id": call_id,
                          "reason": reason, "message": message})


def _incoming_payload(db: Session, c: Call) -> dict | None:
    caller = db.query(User).filter(User.id == c.caller_id).first()
    callee = db.query(User).filter(User.id == c.callee_id).first()
    if caller is None or callee is None:
        return None
    card = public_user(db, caller, callee.id)
    return {
        "type": "call.incoming",
        "call_id": c.id,
        "chat_id": c.chat_id,
        "video": c.video,
        "sdp": c.sdp,
        "ice": list(c.caller_ice),
        "from": {"id": caller.id, "name": card["display_name"], "avatar_url": card["avatar_url"]},
        "ice_servers": ice_servers(callee.id),
        "relay": wants_relay(db, callee, caller.id),
        "ring_left": max(1, int(RING_TIMEOUT - (time.time() - c.created))),
    }


# ─────────────────────────────── завершение ───────────────────────────────

def _release(c: Call) -> None:
    CALLS.pop(c.id, None)
    for uid in (c.caller_id, c.callee_id):
        if BY_USER.get(uid) == c.id:
            BY_USER.pop(uid, None)
    t, c.timer = c.timer, None
    if t is not None and not t.done() and t is not asyncio.current_task():
        t.cancel()


async def end_call(c: Call, status: str, reason: str) -> None:
    """status — что записать в историю (ended/missed/declined/busy/failed),
    reason — что сказать клиентам в call.ended."""
    if CALLS.get(c.id) is not c:
        return
    was_ringing = c.state == "ringing"
    callee_id = c.callee_id
    call_id = c.id
    _release(c)
    if was_ringing:
        try:
            asyncio.get_running_loop().create_task(_push_call_ended(call_id, callee_id))
        except Exception:
            pass
    duration = int(time.time() - c.accepted_at) if c.accepted_at else 0
    payload = {"type": "call.ended", "call_id": c.id, "reason": reason, "duration": duration}
    await manager.send_to_users([c.caller_id, c.callee_id], payload)
    await record(c.chat_id, c.caller_id, c.video, status, duration)


async def record(chat_id: str, caller_id: str, video: bool, status: str, duration: int) -> None:
    """Сообщение-история звонка в чате (как в Telegram)."""
    from app.messaging import deliver
    db = SessionLocal()
    try:
        chat = db.query(Chat).filter(Chat.id == chat_id).first()
        caller = db.query(User).filter(User.id == caller_id).first()
        if chat is None or caller is None:
            return
        expires_at = None
        if chat.ttl_seconds:
            expires_at = datetime.now(timezone.utc) + timedelta(seconds=chat.ttl_seconds)
        msg = Message(chat_id=chat.id, sender_id=caller.id, kind="call", text="",
                      extra=json.dumps({"call": {"video": bool(video), "status": status,
                                                 "duration": int(duration)}}),
                      expires_at=expires_at)
        db.add(msg)
        db.commit()
        db.refresh(msg)
        await deliver(db, chat, msg, caller)
    except Exception:
        db.rollback()
    finally:
        db.close()


async def _ring_timeout(call_id: str, delay: float) -> None:
    try:
        await asyncio.sleep(delay)
    except asyncio.CancelledError:
        return
    c = CALLS.get(call_id)
    if c is not None and c.state == "ringing":
        c.timer = None
        await end_call(c, "missed", "missed")


# ─────────────────────────────── обработчики ───────────────────────────────

def _limited(store: dict, key, limit: int) -> bool:
    q = store.setdefault(key, deque())
    now = time.time()
    while q and now - q[0] > 60:
        q.popleft()
    if len(q) >= limit:
        return True
    q.append(now)
    if len(store) > 5000:          # не копим память бесконечно
        for k in [k for k, v in store.items() if not v][:1000]:
            store.pop(k, None)
    return False


def _spam(user_id: str) -> bool:
    return _limited(_INVITES, user_id, 20)


def _dev(data: dict) -> str:
    return str(data.get("device") or "")[:64]


def _foreign_device(c: Call, uid: str, data: dict) -> bool:
    """Сообщение пришло с другого телефона того же аккаунта, который в звонке не участвует."""
    dev = _dev(data)
    mine = c.caller_dev if uid == c.caller_id else c.callee_dev
    return bool(mine and dev and dev != mine)


async def _push_call(call_id: str, user_id: str, name: str, avatar: str | None,
                     video: bool, chat_id: str) -> None:
    db = SessionLocal()
    try:
        tokens = [t.token for t in db.query(PushToken).filter(PushToken.user_id == user_id)]
    finally:
        db.close()
    if not tokens:
        return
    from app.push import send_push
    body = "📹 Входящий видеозвонок" if video else "📞 Входящий звонок"
    try:
        await run_in_threadpool(
            send_push, tokens, name, body, avatar, "calls_v2", RING_TIMEOUT,
            {
                "type": "call",
                "call_id": call_id,
                "chat_id": chat_id,
                "name": name,
                "video": "1" if video else "0",
                "avatar_url": avatar or "",
            }
        )
    except Exception:
        pass


async def _push_call_ended(call_id: str, user_id: str) -> None:
    db = SessionLocal()
    try:
        tokens = [t.token for t in db.query(PushToken).filter(PushToken.user_id == user_id)]
    finally:
        db.close()
    if not tokens:
        return
    from app.push import send_push
    try:
        await run_in_threadpool(
            send_push, tokens, "Звонок завершён", "", None, "calls_v2", 10,
            {"type": "call_ended", "call_id": call_id}
        )
    except Exception:
        pass


async def _push_if_silent(call_id: str, name: str, avatar: str | None) -> None:
    """Сокет собеседника открыт, но телефон не ответил «звоню» — наверное, приложение
    уснуло в фоне. Тогда будим его пушем."""
    try:
        await asyncio.sleep(SILENT_PUSH_AFTER)
    except asyncio.CancelledError:
        return
    c = CALLS.get(call_id)
    if c is None or c.state != "ringing" or c.rang:
        return
    await _push_call(c.id, c.callee_id, name, avatar, c.video, c.chat_id)


async def _invite(uid: str, data: dict) -> None:
    call_id = str(data.get("call_id") or "")
    chat_id = str(data.get("chat_id") or "")
    sdp = data.get("sdp")
    if not CALL_ID_RE.match(call_id) or not isinstance(sdp, str) or not sdp or len(sdp) > MAX_SDP:
        await _error(uid, call_id or None, "bad_request", "Не удалось начать звонок")
        return
    if call_id in CALLS:
        return
    if _spam(uid):
        await _error(uid, call_id, "flood", "Слишком много звонков, подожди минутку")
        return
    video = bool(data.get("video"))
    db = SessionLocal()
    try:
        caller = db.query(User).filter(User.id == uid).first()
        if caller is None:
            return
        try:
            chat, peer = check_call(db, chat_id, caller)
        except CallError as e:
            await _error(uid, call_id, e.reason, e.message)
            return
        if _limited(_PAIRS, (uid, peer.id), 6):
            await _error(uid, call_id, "flood", "Слишком много звонков, подожди минутку")
            return
        # звонящий начал новый звонок — старый (например, после вылета) больше не нужен
        old = CALLS.get(BY_USER.get(uid, ""))
        if old is not None:
            await end_call(old, "ended" if old.accepted_at else "missed", "ended")
        if peer.id in BY_USER:
            await _send(uid, {"type": "call.ended", "call_id": call_id, "reason": "busy",
                              "duration": 0})
            await record(chat.id, uid, video, "busy", 0)
            return
        c = Call(id=call_id, chat_id=chat.id, caller_id=uid, callee_id=peer.id,
                 video=video, sdp=sdp, created=time.time(), caller_dev=_dev(data))
        CALLS[c.id] = c
        BY_USER[uid] = c.id
        BY_USER[peer.id] = c.id
        c.timer = asyncio.get_running_loop().create_task(_ring_timeout(c.id, RING_TIMEOUT))
        payload = _incoming_payload(db, c)
        if payload is None:
            await end_call(c, "failed", "failed")
            return
        online = manager.is_online(peer.id)
        if online:
            await _send(peer.id, payload)
        name = payload["from"]["name"]
        avatar = payload["from"]["avatar_url"]
    finally:
        db.close()
    await _send(uid, {"type": "call.sent", "call_id": call_id, "online": online})
    # Сразу отправляем вызов в FCM, чтобы телефон в фоне или в кармане проснулся и зазвонил
    asyncio.get_running_loop().create_task(_push_call(call_id, peer.id, name, avatar, video, chat_id))


async def handle(uid: str, data: dict) -> None:
    """Сообщение call.* от клиента по WebSocket."""
    t = data.get("type")
    if t == "call.invite":
        await _invite(uid, data)
        return
    if t == "call.sync":
        await _sync(uid, data)
        return
    call_id = str(data.get("call_id") or "")
    c = CALLS.get(call_id)
    if c is None or uid not in (c.caller_id, c.callee_id):
        if t not in ("call.ice", "call.end", "call.ringing", "call.decline", "call.restart"):
            await _error(uid, call_id or None, "gone", "Звонок уже завершён")
        return
    other = c.other(uid)
    if t not in ("call.accept", "call.ringing", "call.decline") and _foreign_device(c, uid, data):
        return
    if t == "call.ringing":
        if uid == c.callee_id and c.state == "ringing":
            c.rang = True
            await _send(c.caller_id, {"type": "call.ringing", "call_id": c.id})
    elif t == "call.accept":
        sdp = data.get("sdp")
        if uid != c.callee_id:
            return
        if c.state == "active":
            # ответили сразу с двух телефонов — второй должен отключиться
            if _dev(data) != c.callee_dev:
                await _send(c.callee_id, {"type": "call.taken", "call_id": c.id,
                                          "device": c.callee_dev})
            return
        if not isinstance(sdp, str) or not sdp or len(sdp) > MAX_SDP:
            return
        c.state = "active"
        c.accepted_at = time.time()
        c.callee_dev = _dev(data)
        c.answer = sdp
        if c.timer is not None:
            c.timer.cancel()
            c.timer = None
        await _send(c.caller_id, {"type": "call.accepted", "call_id": c.id, "sdp": sdp})
        # остальные устройства собеседника перестают звонить
        await _send(c.callee_id, {"type": "call.taken", "call_id": c.id, "device": c.callee_dev})
    elif t == "call.decline":
        if uid == c.callee_id and c.state == "ringing":
            await end_call(c, "declined", "declined")
    elif t == "call.end":
        reason = data.get("reason")
        if c.state == "ringing":
            if uid == c.caller_id:
                await end_call(c, "missed", "cancelled")
            elif reason == "busy":
                await end_call(c, "busy", "busy")      # у собеседника уже идёт разговор
            elif reason == "failed":
                await end_call(c, "failed", "failed")
            else:
                await end_call(c, "declined", "declined")
        else:
            await end_call(c, "failed" if reason == "failed" else "ended",
                           "failed" if reason == "failed" else "ended")
    elif t == "call.ice":
        cand = data.get("candidate")
        if not isinstance(cand, dict) or len(json.dumps(cand)) > 2000:
            return
        if uid == c.caller_id and c.state == "ringing":
            if len(c.caller_ice) < MAX_ICE:
                c.caller_ice.append(cand)
        await _send(other, {"type": "call.ice", "call_id": c.id, "candidate": cand})
    elif t == "call.sdp":
        sdp = data.get("sdp")
        kind = data.get("sdp_type")
        if c.state != "active" or kind not in ("offer", "answer") or not isinstance(sdp, str) \
                or not sdp or len(sdp) > MAX_SDP:
            return
        await _send(other, {"type": "call.sdp", "call_id": c.id, "sdp": sdp, "sdp_type": kind})
    elif t == "call.restart":
        # собеседник сменил сеть — просим звонящего перезапустить соединение
        if c.state == "active":
            await _send(other, {"type": "call.restart", "call_id": c.id})


async def _sync(uid: str, data: dict) -> None:
    """Клиент переподключился и говорит, какой звонок у него идёт (или никакого).
    Сервер доотправляет потерянное или закрывает «зависший» звонок."""
    client_call = str(data.get("call_id") or "")
    cid = BY_USER.get(uid)
    c = CALLS.get(cid) if cid else None
    if c is None:
        if client_call:
            await _send(uid, {"type": "call.ended", "call_id": client_call, "reason": "ended",
                              "duration": 0})
        return
    if _foreign_device(c, uid, data):
        return
    if client_call != c.id:
        if c.state == "ringing" and uid == c.callee_id:
            return                       # входящий уже показан при подключении
        if uid == c.caller_id or c.state == "active":
            # приложение перезапустилось — старый звонок продолжить нельзя
            if c.state == "ringing":
                await end_call(c, "missed", "cancelled")
            else:
                await end_call(c, "ended", "ended")
        return
    if c.state == "active" and uid == c.caller_id and c.answer:
        await _send(uid, {"type": "call.accepted", "call_id": c.id, "sdp": c.answer})


# ─────────────────────────────── подключения ───────────────────────────────

async def on_connect(uid: str, ws) -> None:
    """Человек открыл приложение (например, из пуша) — покажем входящий звонок."""
    cid = BY_USER.get(uid)
    c = CALLS.get(cid) if cid else None
    if c is None or c.callee_id != uid or c.state != "ringing":
        return
    db = SessionLocal()
    try:
        payload = _incoming_payload(db, c)
    finally:
        db.close()
    if payload is not None:
        try:
            await ws.send_json(payload)
        except Exception:
            pass


async def _gone_check(call_id: str, delay: float) -> None:
    await asyncio.sleep(delay)
    c = CALLS.get(call_id)
    if c is None:
        return
    if c.state == "ringing" and not manager.is_online(c.caller_id):
        await end_call(c, "missed", "cancelled")
    elif c.state == "active" and not manager.is_online(c.caller_id) \
            and not manager.is_online(c.callee_id):
        await end_call(c, "ended", "ended")


async def on_disconnect(uid: str) -> None:
    if manager.is_online(uid):
        return
    cid = BY_USER.get(uid)
    c = CALLS.get(cid) if cid else None
    if c is None:
        return
    loop = asyncio.get_running_loop()
    if c.state == "ringing" and uid == c.caller_id:
        loop.create_task(_gone_check(c.id, CALLER_GONE_GRACE))
    elif c.state == "active":
        loop.create_task(_gone_check(c.id, ABANDON_GRACE))


def call_preview(extra: dict | None, outgoing: bool) -> str:
    """Текст для списка чатов и пушей: «📞 Пропущенный звонок» и т.п."""
    info = (extra or {}).get("call") or {}
    video = bool(info.get("video"))
    status = info.get("status")
    what = "видеозвонок" if video else "звонок"
    icon = "📹" if video else "📞"
    if status == "busy" and outgoing:
        text = "Линия занята"
    elif status in ("missed", "busy"):
        text = f"Отменённый {what}" if outgoing else f"Пропущенный {what}"
    elif status == "declined":
        text = f"Отклонённый {what}"
    elif status == "failed":
        text = f"Неудачный {what}"
    else:
        text = ("Исходящий " if outgoing else "Входящий ") + what
        d = int(info.get("duration") or 0)
        if d > 0:
            text += f" · {d // 60}:{d % 60:02d}"
    return f"{icon} {text}"
