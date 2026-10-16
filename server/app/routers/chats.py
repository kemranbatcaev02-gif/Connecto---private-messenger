import json
import re
import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import or_, func
from sqlalchemy.orm import Session

from app.deps import get_db, get_current_user
from app.models.user import User
from app.models.chat import (Chat, ChatMember, Message, ChatRead, MessageReaction,
                             ChatBan)
from app.schemas.chat import ChatCreate, MessageCreate, MessageEdit, PinUpdate
from app.realtime import manager
from app.privacy import (is_blocked, allowed, as_utc, is_premium, public_user,
                         is_contact, emoji_status_of)
from app.messaging import (deliver, message_dict, reactions_for, preview_text,
                           member_ids, service_message, forwarded_name_of, alive,
                           is_sealed, FREE_EFFECTS, PREMIUM_EFFECTS, TTL_VALUES)
from app.config import settings
from app import sysbot

router = APIRouter(prefix="/chats", tags=["chats"])
join_router = APIRouter(tags=["chats"])

HANDLE_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9_]{3,31}$")


# ── помощники ──

def _name(u: User | None) -> str:
    if u is None:
        return "Удалённый аккаунт"
    return u.display_name or u.username


def _get_chat(db: Session, chat_id: str) -> Chat:
    chat = db.query(Chat).filter(Chat.id == chat_id).first()
    if chat is None:
        raise HTTPException(status_code=404, detail="Чат не найден")
    return chat


def _member(db: Session, chat_id: str, user_id: str) -> ChatMember | None:
    return (db.query(ChatMember)
            .filter(ChatMember.chat_id == chat_id, ChatMember.user_id == user_id).first())


def _ensure_member(db: Session, chat_id: str, user_id: str) -> ChatMember:
    m = _member(db, chat_id, user_id)
    if m is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Нет доступа к этому чату")
    return m


def _is_admin(m: ChatMember | None) -> bool:
    return m is not None and m.role in ("owner", "admin")


def _require_admin(db: Session, chat: Chat, user_id: str) -> ChatMember:
    m = _ensure_member(db, chat.id, user_id)
    if chat.type == "direct" or not _is_admin(m):
        raise HTTPException(status_code=403, detail="Нужны права администратора")
    return m


def _peer(db: Session, chat: Chat, me_id: str) -> User | None:
    if chat.type != "direct":
        return None
    rows = db.query(ChatMember).filter(ChatMember.chat_id == chat.id).all()
    me = next((r for r in rows if r.user_id == me_id), None)
    if chat.is_system and sysbot.is_support(me):
        # админ в обращении: собеседник — человек, написавший в поддержку
        owner = sysbot.support_owner(db, chat)
        return owner
    # скрытые админы поддержки собеседниками не считаются
    other = next((r.user_id for r in rows
                  if r.user_id != me_id and r.role != sysbot.SUPPORT_ROLE), None)
    return db.query(User).filter(User.id == other).first() if other else None


def _visible_member_ids(db: Session, chat: Chat, mem: ChatMember | None) -> list[str]:
    """Участники, которых видит mem (админов поддержки обычный человек не видит)."""
    rows = db.query(ChatMember).filter(ChatMember.chat_id == chat.id).all()
    if chat.is_system and not sysbot.is_support(mem):
        rows = [r for r in rows if r.role != sysbot.SUPPORT_ROLE]
    return [r.user_id for r in rows]


def presence_of(db: Session, peer: User | None, viewer_id: str):
    """(online, last_seen) с учётом приватности и блокировок."""
    if peer is None or peer.is_bot:
        return False, None
    if is_blocked(db, peer.id, viewer_id) or is_blocked(db, viewer_id, peer.id):
        return False, None
    rule = peer.lastseen_privacy or "all"
    if rule == "none":
        return False, None
    if rule == "contacts" and not is_contact(db, peer.id, viewer_id):
        return False, None
    return manager.is_online(peer.id), as_utc(peer.last_seen)


def _last_read(db: Session, chat_id: str, user_id: str):
    row = (db.query(ChatRead)
           .filter(ChatRead.chat_id == chat_id, ChatRead.user_id == user_id).first())
    return as_utc(row.last_read_at) if row else None


def _cleared(mem: ChatMember | None):
    return as_utc(mem.cleared_at) if mem is not None and mem.cleared_at else None


def _visible(q, mem: ChatMember | None):
    """Скрыть сообщения, которые пользователь удалил/очистил у себя."""
    c = _cleared(mem)
    return q.filter(Message.created_at > c) if c else q


def _others_last_read(db: Session, chat_id: str, me_id: str, only: str | None = None):
    """Самый поздний момент, до которого прочитал кто-то из собеседников
    (кто отключил отчёты о прочтении — не учитывается). only — учитывать только его."""
    q = (db.query(ChatRead, User).join(User, User.id == ChatRead.user_id)
         .filter(ChatRead.chat_id == chat_id, ChatRead.user_id != me_id))
    if only:
        q = q.filter(ChatRead.user_id == only)
    rows = q.all()
    times = [as_utc(r.last_read_at) for r, u in rows
             if r.last_read_at and (u.read_receipts is None or u.read_receipts)]
    return max(times) if times else None


def _support_reader(db: Session, chat: Chat, mem: ChatMember | None) -> str | None:
    """Админу в обращении ✓✓ ставит только сам человек, а не другие админы."""
    if chat.is_system and sysbot.is_support(mem):
        owner = sysbot.support_owner(db, chat)
        return owner.id if owner else "-"
    return None


def _invite_link(chat: Chat) -> str | None:
    if not chat.invite_code:
        return None
    return f"{settings.public_base}/j/{chat.invite_code}"


def _handle_taken(db: Session, handle: str, chat_id: str | None = None) -> bool:
    if db.query(User).filter(func.lower(User.handle) == handle.lower()).first():
        return True
    q = db.query(Chat).filter(func.lower(Chat.handle) == handle.lower())
    if chat_id:
        q = q.filter(Chat.id != chat_id)
    return q.first() is not None


def chat_out(db: Session, chat: Chat, me: User, mem: ChatMember | None) -> dict:
    support = bool(chat.is_system and sysbot.is_support(mem))
    bot_id = sysbot.get_bot(db).id if support else None
    lq = alive(_visible(db.query(Message).filter(Message.chat_id == chat.id), mem))
    if support:
        lq = sysbot.support_filter(lq, bot_id)
    last = lq.order_by(Message.created_at.desc()).first()
    if chat.is_system:
        ids = _visible_member_ids(db, chat, mem)
        count = len(ids)
    else:
        count = db.query(ChatMember).filter(ChatMember.chat_id == chat.id).count()
        ids = member_ids(db, chat.id) if count <= 200 else []
    # для админа в обращении «свои» — и его ответы, и ответы других админов (они от Connecto)
    mine_ids = {me.id, bot_id} if support else {me.id}
    # непрочитанные
    unread = 0
    if mem is not None:
        since = _last_read(db, chat.id, me.id)
        joined = as_utc(mem.joined_at)
        if since is None or (joined and joined > since):
            since = joined
        cl = _cleared(mem)
        if cl and (since is None or cl > since):
            since = cl
        q = db.query(Message).filter(Message.chat_id == chat.id,
                                     Message.sender_id.notin_(list(mine_ids)))
        if since is not None:
            q = q.filter(Message.created_at > since)
        unread = q.count()
    last_sender = None
    if last is not None and chat.type == "group" and last.kind != "service":
        last_sender = ("Вы" if last.sender_id == me.id
                       else _name(db.query(User).filter(User.id == last.sender_id).first()))
    last_read_by_peer = False
    if last is not None and last.sender_id in mine_ids:
        lr = _others_last_read(db, chat.id, me.id, only=_support_reader(db, chat, mem))
        last_read_by_peer = bool(lr and as_utc(last.created_at) <= lr
                                 and (me.read_receipts is None or me.read_receipts))
    out = {
        "id": chat.id,
        "type": chat.type,
        "title": chat.title,
        "description": chat.description,
        "handle": chat.handle,
        "avatar_url": chat.avatar_url,
        "created_at": chat.created_at.isoformat() if chat.created_at else None,
        "last_message": preview_text(last, me.id),
        # зашифрованное последнее сообщение — приложение расшифрует превью само
        "last_enc": (last.enc if last is not None and not is_sealed(last, me.id) else None),
        "last_kind": last.kind if last else None,
        "last_time": last.created_at.isoformat() if last and last.created_at else None,
        "last_sender": last_sender,
        "last_mine": bool(last and last.sender_id in mine_ids),
        "last_read": last_read_by_peer,
        "members": ids,
        "member_count": count,
        "my_role": mem.role if mem else None,
        "is_member": mem is not None,
        "unread_count": unread,
        "muted_until": (mem.muted_until or 0) if mem else 0,
        "members_can_send": bool(chat.members_can_send),
        "members_can_add": bool(chat.members_can_add),
        # у админа обращение выглядит как обычная личка с человеком + метка «Поддержка»
        "is_system": bool(chat.is_system) and not support,
        "support": support,
        "support_bot_id": bot_id,
        "invite_link": _invite_link(chat) if _is_admin(mem) else None,
        "peer_id": None,
        "peer_online": False,
        "peer_last_seen": None,
        "peer_is_bot": False,
        "is_verified": bool(chat.is_verified),
        "ttl_seconds": chat.ttl_seconds or 0,
        "peer_premium": False,
        "peer_emoji_status": None,
        "can_send": _can_send_flag(chat, mem),
    }
    if chat.type == "direct":
        peer = _peer(db, chat, me.id)
        if peer is not None:
            hidden = is_blocked(db, peer.id, me.id)
            online, seen = presence_of(db, peer, me.id)
            out.update({
                "title": _name(peer),
                "avatar_url": None if hidden or not allowed(db, peer, me.id, "avatar") else peer.avatar_url,
                "frame": {"id": peer.avatar_frame, "url": f"/media/shop/{peer.avatar_frame}.png"} if peer.avatar_frame else None,
                "peer_id": peer.id,
                "peer_online": online,
                "peer_last_seen": seen.isoformat() if seen else None,
                "peer_is_bot": bool(peer.is_bot),
                "is_verified": bool(peer.is_verified),
                "peer_premium": is_premium(peer),
                "peer_emoji_status": emoji_status_of(peer),
                "handle": peer.handle,
            })
        else:
            out["title"] = "Удалённый аккаунт"
    return out


def _can_send_flag(chat: Chat, mem: ChatMember | None) -> bool:
    if mem is None:
        return False
    if chat.type == "channel":
        return _is_admin(mem)
    if chat.type == "group":
        return bool(chat.members_can_send) or _is_admin(mem)
    return True


# ── создание и список ──

@router.post("", status_code=201)
async def create_chat(data: ChatCreate, db: Session = Depends(get_db),
                      user: User = Depends(get_current_user)):
    if data.type == "direct":
        ids = set(data.member_ids) | {user.id}
        if len(ids) != 2:
            raise HTTPException(status_code=400, detail="Личный чат — ровно два человека")
        other_id = next(i for i in ids if i != user.id)
        other = db.query(User).filter(User.id == other_id).first()
        if other is None:
            raise HTTPException(status_code=404, detail="Пользователь не найден")
        if other.is_bot and other.email == sysbot.SYSTEM_EMAIL:
            c = sysbot.system_chat(db, user)
            return chat_out(db, c, user, _member(db, c.id, user.id))
        # уже есть — возвращаем
        mine = db.query(ChatMember.chat_id).filter(ChatMember.user_id == user.id)
        for c in (db.query(Chat).join(ChatMember, ChatMember.chat_id == Chat.id)
                  .filter(Chat.type == "direct", Chat.is_system == False,  # noqa: E712
                          ChatMember.user_id == other_id, Chat.id.in_(mine)).all()):
            return chat_out(db, c, user, _member(db, c.id, user.id))
        chat = Chat(type="direct")
        db.add(chat)
        db.flush()
        db.add(ChatMember(chat_id=chat.id, user_id=user.id, role="member"))
        db.add(ChatMember(chat_id=chat.id, user_id=other_id, role="member"))
        db.commit()
        db.refresh(chat)
        return chat_out(db, chat, user, _member(db, chat.id, user.id))

    title = (data.title or "").strip()
    if not title:
        raise HTTPException(status_code=400, detail="Укажи название")
    handle = (data.handle or "").strip().lstrip("@") or None
    if handle:
        if not HANDLE_RE.match(handle):
            raise HTTPException(status_code=400,
                                detail="Ссылка: 4–32 символа, латиница, цифры и _")
        if _handle_taken(db, handle):
            raise HTTPException(status_code=409, detail="Эта ссылка уже занята")
    chat = Chat(type=data.type, title=title[:128],
                description=(data.description or "").strip()[:500] or None,
                avatar_url=data.avatar_url or None, handle=handle,
                invite_code=secrets.token_urlsafe(8), owner_id=user.id)
    db.add(chat)
    db.flush()
    db.add(ChatMember(chat_id=chat.id, user_id=user.id, role="owner"))
    skipped = []
    added_names = []
    for uid in set(data.member_ids) - {user.id}:
        u = db.query(User).filter(User.id == uid).first()
        if u is None or u.is_bot and u.bot_owner_id is None:
            continue
        if not u.is_bot and not allowed(db, u, user.id, "invites"):
            skipped.append({"id": u.id, "name": _name(u)})
            continue
        db.add(ChatMember(chat_id=chat.id, user_id=uid, role="member"))
        added_names.append(_name(u))
    db.commit()
    db.refresh(chat)
    if chat.type == "group":
        msg = service_message(db, chat, user, f"{_name(user)} создал(а) группу «{chat.title}»")
    else:
        msg = service_message(db, chat, user, f"Канал «{chat.title}» создан")
    await deliver(db, chat, msg, user)
    out = chat_out(db, chat, user, _member(db, chat.id, user.id))
    out["skipped"] = skipped
    return out


@router.get("")
def list_chats(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    result = []
    from app.config import is_admin_email
    for m in db.query(ChatMember).filter(ChatMember.user_id == user.id).all():
        chat = db.query(Chat).filter(Chat.id == m.chat_id).first()
        if not chat:
            continue
        if sysbot.is_support(m) and (not is_admin_email(user.email)
                                     or sysbot.support_owner(db, chat) is None):
            continue   # больше не админ или человек удалил аккаунт
        out = chat_out(db, chat, user, m)
        if chat.type == "direct" and m.cleared_at and out["last_time"] is None:
            continue   # удалён «у себя» и новых сообщений нет
        result.append(out)
    result.sort(key=lambda c: c["last_time"] or c["created_at"] or "", reverse=True)
    return result


# ── публичные чаты и приглашения ──

@router.get("/public/search")
def search_public(q: str, db: Session = Depends(get_db),
                  user: User = Depends(get_current_user)):
    q = q.strip().lstrip("@")
    if len(q) < 2:
        return []
    like = f"%{q}%"
    rows = (db.query(Chat).filter(Chat.handle.isnot(None))
            .filter(or_(Chat.handle.ilike(like), Chat.title.ilike(like)))
            .limit(30).all())
    return [chat_out(db, c, user, _member(db, c.id, user.id)) for c in rows]


def _join(db: Session, chat: Chat, user: User) -> ChatMember:
    if db.query(ChatBan).filter(ChatBan.chat_id == chat.id, ChatBan.user_id == user.id).first():
        raise HTTPException(status_code=403, detail="Вас исключили из этого чата")
    m = _member(db, chat.id, user.id)
    if m is not None:
        return m
    m = ChatMember(chat_id=chat.id, user_id=user.id, role="member")
    db.add(m)
    db.commit()
    db.refresh(m)
    return m


@join_router.get("/join/{code}")
def join_preview(code: str, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    chat = db.query(Chat).filter(Chat.invite_code == code).first()
    if chat is None:
        raise HTTPException(status_code=404, detail="Ссылка недействительна")
    return chat_out(db, chat, user, _member(db, chat.id, user.id))


@join_router.post("/join/{code}")
async def join_by_code(code: str, db: Session = Depends(get_db),
                       user: User = Depends(get_current_user)):
    chat = db.query(Chat).filter(Chat.invite_code == code).first()
    if chat is None:
        raise HTTPException(status_code=404, detail="Ссылка недействительна")
    was = _member(db, chat.id, user.id) is not None
    m = _join(db, chat, user)
    if not was and chat.type == "group":
        msg = service_message(db, chat, user, f"{_name(user)} присоединился(-ась) к группе")
        await deliver(db, chat, msg, user)
    return chat_out(db, chat, user, m)


@router.post("/{chat_id}/join")
async def join_public(chat_id: str, db: Session = Depends(get_db),
                      user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    if not chat.handle:
        raise HTTPException(status_code=403, detail="Это закрытый чат — нужна ссылка-приглашение")
    was = _member(db, chat.id, user.id) is not None
    m = _join(db, chat, user)
    if not was and chat.type == "group":
        msg = service_message(db, chat, user, f"{_name(user)} присоединился(-ась) к группе")
        await deliver(db, chat, msg, user)
    return chat_out(db, chat, user, m)


# ── информация о чате ──

def _can_view(db: Session, chat: Chat, user_id: str) -> ChatMember | None:
    m = _member(db, chat.id, user_id)
    if m is None and not chat.handle:
        raise HTTPException(status_code=403, detail="Нет доступа к этому чату")
    return m


@router.get("/{chat_id}")
def chat_info(chat_id: str, db: Session = Depends(get_db),
              user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    m = _can_view(db, chat, user.id)
    return chat_out(db, chat, user, m)


class ChatEdit(BaseModel):
    title: str | None = Field(default=None, max_length=128)
    description: str | None = Field(default=None, max_length=500)
    avatar_url: str | None = None
    handle: str | None = None          # "" — сделать приватным
    members_can_send: bool | None = None
    members_can_add: bool | None = None


@router.patch("/{chat_id}")
async def edit_chat(chat_id: str, data: ChatEdit, db: Session = Depends(get_db),
                    user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    _require_admin(db, chat, user.id)
    notes = []
    if data.title is not None and data.title.strip() and data.title.strip() != chat.title:
        chat.title = data.title.strip()
        notes.append(f"{_name(user)} изменил(а) название на «{chat.title}»")
    if data.description is not None:
        chat.description = data.description.strip() or None
    if data.avatar_url is not None and data.avatar_url != (chat.avatar_url or ""):
        chat.avatar_url = data.avatar_url or None
        notes.append(f"{_name(user)} обновил(а) фото")
    if data.handle is not None:
        h = data.handle.strip().lstrip("@")
        if h:
            if not HANDLE_RE.match(h):
                raise HTTPException(status_code=400,
                                    detail="Ссылка: 4–32 символа, латиница, цифры и _")
            if _handle_taken(db, h, chat.id):
                raise HTTPException(status_code=409, detail="Эта ссылка уже занята")
            chat.handle = h
        else:
            chat.handle = None
    if data.members_can_send is not None:
        chat.members_can_send = data.members_can_send
    if data.members_can_add is not None:
        chat.members_can_add = data.members_can_add
    db.commit()
    for text in notes:
        if chat.type == "group":
            msg = service_message(db, chat, user, text)
            await deliver(db, chat, msg, user)
    await manager.send_to_users(member_ids(db, chat.id),
                                {"type": "chat_updated", "chat_id": chat.id})
    return chat_out(db, chat, user, _member(db, chat.id, user.id))


@router.post("/{chat_id}/invite")
def regenerate_invite(chat_id: str, db: Session = Depends(get_db),
                      user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    _require_admin(db, chat, user.id)
    chat.invite_code = secrets.token_urlsafe(8)
    db.commit()
    return {"invite_link": _invite_link(chat), "invite_code": chat.invite_code}


# ── участники ──

@router.get("/{chat_id}/members")
def list_members(chat_id: str, q: str = "", db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    m = _ensure_member(db, chat.id, user.id)
    if chat.type == "channel" and not _is_admin(m):
        raise HTTPException(status_code=403, detail="Список подписчиков видят только админы")
    rows = (db.query(ChatMember, User).join(User, User.id == ChatMember.user_id)
            .filter(ChatMember.chat_id == chat.id).all())
    order = {"owner": 0, "admin": 1, "member": 2}
    out = []
    ql = q.strip().lower()
    hide_support = chat.is_system and not sysbot.is_support(m)
    for cm, u in rows:
        if hide_support and cm.role == sysbot.SUPPORT_ROLE:
            continue
        if ql and ql not in (u.display_name or "").lower() and ql not in (u.handle or "").lower():
            continue
        card = public_user(db, u, user.id)
        online, seen = presence_of(db, u, user.id)
        card.update({"role": cm.role, "online": online,
                     "last_seen": seen.isoformat() if seen else None,
                     "joined_at": cm.joined_at.isoformat() if cm.joined_at else None})
        out.append(card)
    out.sort(key=lambda x: (order.get(x["role"], 3), not x["online"], x["display_name"].lower()))
    return out


class AddMembers(BaseModel):
    user_ids: list[str]


@router.post("/{chat_id}/members")
async def add_members(chat_id: str, data: AddMembers, db: Session = Depends(get_db),
                      user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    if chat.type == "direct":
        raise HTTPException(status_code=400, detail="В личный чат нельзя добавить участников")
    me = _ensure_member(db, chat.id, user.id)
    can = _is_admin(me) or (chat.type == "group" and chat.members_can_add)
    if not can:
        raise HTTPException(status_code=403, detail="Добавлять участников могут только админы")
    added, skipped = [], []
    for uid in dict.fromkeys(data.user_ids):
        u = db.query(User).filter(User.id == uid).first()
        if u is None or (u.is_bot and u.bot_owner_id is None):
            continue
        if _member(db, chat.id, uid) is not None:
            continue
        if not u.is_bot and not allowed(db, u, user.id, "invites"):
            skipped.append({"id": u.id, "name": _name(u),
                            "reason": "запретил(а) приглашать себя — отправь ссылку"})
            continue
        db.query(ChatBan).filter(ChatBan.chat_id == chat.id, ChatBan.user_id == uid).delete()
        db.add(ChatMember(chat_id=chat.id, user_id=uid, role="member"))
        added.append(u)
    db.commit()
    if added and chat.type == "group":
        names = ", ".join(_name(u) for u in added)
        msg = service_message(db, chat, user, f"{_name(user)} добавил(а) {names}")
        await deliver(db, chat, msg, user)
    await manager.send_to_users([u.id for u in added],
                                {"type": "chat_added", "chat_id": chat.id})
    return {"added": [u.id for u in added], "skipped": skipped}


@router.delete("/{chat_id}/members/{user_id}", status_code=204)
async def kick_member(chat_id: str, user_id: str, db: Session = Depends(get_db),
                      user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    me = _require_admin(db, chat, user.id)
    target = _member(db, chat.id, user_id)
    if target is None:
        return
    if target.role == "owner":
        raise HTTPException(status_code=403, detail="Нельзя исключить владельца")
    if target.role == "admin" and me.role != "owner":
        raise HTTPException(status_code=403, detail="Админа может исключить только владелец")
    db.delete(target)
    db.add(ChatBan(chat_id=chat.id, user_id=user_id))
    db.commit()
    tu = db.query(User).filter(User.id == user_id).first()
    if chat.type == "group":
        msg = service_message(db, chat, user, f"{_name(user)} исключил(а) {_name(tu)}")
        await deliver(db, chat, msg, user)
    await manager.send_to_users([user_id], {"type": "chat_deleted", "chat_id": chat.id})


@router.delete("/{chat_id}/bans/{user_id}", status_code=204)
def unban_member(chat_id: str, user_id: str, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    _require_admin(db, chat, user.id)
    db.query(ChatBan).filter(ChatBan.chat_id == chat.id, ChatBan.user_id == user_id).delete()
    db.commit()


@router.get("/{chat_id}/bans")
def list_bans(chat_id: str, db: Session = Depends(get_db),
              user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    _require_admin(db, chat, user.id)
    ids = [b.user_id for b in db.query(ChatBan).filter(ChatBan.chat_id == chat.id)]
    if not ids:
        return []
    return [public_user(db, u, user.id) for u in db.query(User).filter(User.id.in_(ids))]


class RoleIn(BaseModel):
    role: str = Field(pattern=r"^(admin|member)$")


@router.patch("/{chat_id}/members/{user_id}")
async def set_role(chat_id: str, user_id: str, data: RoleIn, db: Session = Depends(get_db),
                   user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    me = _ensure_member(db, chat.id, user.id)
    if me.role != "owner":
        raise HTTPException(status_code=403, detail="Назначать админов может только владелец")
    target = _member(db, chat.id, user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="Участник не найден")
    if target.role == "owner":
        raise HTTPException(status_code=400, detail="Это владелец")
    target.role = data.role
    db.commit()
    await manager.send_to_users(member_ids(db, chat.id),
                                {"type": "chat_updated", "chat_id": chat.id})
    return {"ok": True, "role": target.role}


class TransferIn(BaseModel):
    user_id: str


@router.post("/{chat_id}/transfer")
async def transfer_owner(chat_id: str, data: TransferIn, db: Session = Depends(get_db),
                         user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    me = _ensure_member(db, chat.id, user.id)
    if me.role != "owner":
        raise HTTPException(status_code=403, detail="Передать права может только владелец")
    target = _member(db, chat.id, data.user_id)
    if target is None or data.user_id == user.id:
        raise HTTPException(status_code=404, detail="Участник не найден")
    target.role = "owner"
    me.role = "admin"
    chat.owner_id = data.user_id
    db.commit()
    await manager.send_to_users(member_ids(db, chat.id),
                                {"type": "chat_updated", "chat_id": chat.id})
    return {"ok": True}


async def _leave(db: Session, chat: Chat, user: User) -> None:
    m = _member(db, chat.id, user.id)
    if m is None:
        return
    was_owner = m.role == "owner"
    db.delete(m)
    db.query(ChatRead).filter(ChatRead.chat_id == chat.id, ChatRead.user_id == user.id).delete()
    db.commit()
    rest = (db.query(ChatMember).filter(ChatMember.chat_id == chat.id)
            .order_by(ChatMember.joined_at.asc()).all())
    if chat.type in ("group", "channel"):
        if not rest:
            _delete_chat_rows(db, chat)
            return
        if was_owner:
            nxt = next((r for r in rest if r.role == "admin"), rest[0])
            nxt.role = "owner"
            chat.owner_id = nxt.user_id
            db.commit()
        if chat.type == "group":
            msg = service_message(db, chat, user, f"{_name(user)} покинул(а) группу")
            await deliver(db, chat, msg, user)


def _delete_chat_rows(db: Session, chat: Chat) -> None:
    db.query(MessageReaction).filter(MessageReaction.chat_id == chat.id).delete()
    db.query(Message).filter(Message.chat_id == chat.id).delete()
    db.query(ChatRead).filter(ChatRead.chat_id == chat.id).delete()
    db.query(ChatMember).filter(ChatMember.chat_id == chat.id).delete()
    db.query(ChatBan).filter(ChatBan.chat_id == chat.id).delete()
    db.query(Chat).filter(Chat.id == chat.id).delete()
    db.commit()


@router.post("/{chat_id}/leave", status_code=204)
async def leave_chat(chat_id: str, db: Session = Depends(get_db),
                     user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    await _leave(db, chat, user)


@router.delete("/{chat_id}", status_code=204)
async def delete_chat(chat_id: str, scope: str = "me",
                      db: Session = Depends(get_db),
                      user: User = Depends(get_current_user)):
    """direct: scope=me — убрать у себя, both — у обоих.
    group/channel: me — выйти, both — удалить для всех (только владелец)."""
    chat = _get_chat(db, chat_id)
    m = _ensure_member(db, chat.id, user.id)
    if chat.is_system and sysbot.is_support(m):
        # админ убирает обращение у себя (вернётся, если человек напишет снова)
        db.delete(m)
        db.query(ChatRead).filter(ChatRead.chat_id == chat.id, ChatRead.user_id == user.id).delete()
        db.commit()
        return
    if chat.type == "direct":
        if scope == "both":
            members = member_ids(db, chat.id)
            _delete_chat_rows(db, chat)
            await manager.send_to_users([x for x in members if x != user.id],
                                        {"type": "chat_deleted", "chat_id": chat_id})
        else:
            # не выходим из чата (иначе собеседник «потеряет» нас) — просто прячем историю
            m.cleared_at = datetime.now(timezone.utc)
            db.commit()
        return
    if scope == "both":
        if m.role != "owner":
            raise HTTPException(status_code=403, detail="Удалить для всех может только владелец")
        members = member_ids(db, chat.id)
        _delete_chat_rows(db, chat)
        await manager.send_to_users([x for x in members if x != user.id],
                                    {"type": "chat_deleted", "chat_id": chat_id})
        return
    await _leave(db, chat, user)


class MuteIn(BaseModel):
    until: int = 0   # 0 — включить звук, -1 — навсегда, иначе epoch ms


@router.put("/{chat_id}/mute")
def mute_chat(chat_id: str, data: MuteIn, db: Session = Depends(get_db),
              user: User = Depends(get_current_user)):
    m = _ensure_member(db, chat_id, user.id)
    m.muted_until = data.until
    db.commit()
    return {"muted_until": m.muted_until}


# ── сообщения ──

def _serialize(db: Session, chat: Chat, msgs: list[Message], viewer: User) -> list[dict]:
    senders = {u.id: u for u in db.query(User).filter(
        User.id.in_({m.sender_id for m in msgs}))} if msgs else {}
    mem = _member(db, chat.id, viewer.id) if chat.is_system else None
    read_ts = _others_last_read(db, chat.id, viewer.id, only=_support_reader(db, chat, mem))
    see_reads = viewer.read_receipts is None or viewer.read_receipts
    mine_ids = {viewer.id}
    as_id = viewer.id
    if chat.is_system and sysbot.is_support(mem):
        as_id = sysbot.get_bot(db).id   # реакции поддержки — «мои» для админа
        mine_ids.add(as_id)
    reacts = reactions_for(db, [m.id for m in msgs], as_id)
    out = []
    for m in msgs:
        d = message_dict(m, chat, senders.get(m.sender_id), reacts.get(m.id),
                         forwarded_name_of(db, m) if m.forwarded_from else None,
                         viewer_id=viewer.id)
        d["read"] = bool(see_reads and m.sender_id in mine_ids and read_ts is not None
                         and as_utc(m.created_at) <= read_ts)
        out.append(d)
    return out


@router.get("/{chat_id}/messages")
def get_messages(chat_id: str, limit: int = 400, before: str | None = None,
                 db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    mem = _can_view(db, chat, user.id)
    limit = max(1, min(limit, 1000))
    q = alive(_visible(db.query(Message).filter(Message.chat_id == chat_id), mem))
    if chat.is_system and sysbot.is_support(mem):
        q = sysbot.support_filter(q, sysbot.get_bot(db).id)
    if before:
        ref = db.query(Message).filter(Message.id == before).first()
        if ref is not None:
            q = q.filter(Message.created_at < ref.created_at)
    msgs = q.order_by(Message.created_at.desc()).limit(limit).all()
    msgs.reverse()
    return _serialize(db, chat, msgs, user)


@router.post("/{chat_id}/read", status_code=204)
async def mark_read(chat_id: str, db: Session = Depends(get_db),
                    user: User = Depends(get_current_user)):
    m = _member(db, chat_id, user.id)
    if m is None:
        return
    row = (db.query(ChatRead)
           .filter(ChatRead.chat_id == chat_id, ChatRead.user_id == user.id).first())
    now = datetime.now(timezone.utc)
    if row is None:
        db.add(ChatRead(chat_id=chat_id, user_id=user.id, last_read_at=now))
    else:
        row.last_read_at = now
    db.commit()
    if user.read_receipts is None or user.read_receipts:
        others = [uid for uid in member_ids(db, chat_id) if uid != user.id]
        chat = db.query(Chat).filter(Chat.id == chat_id).first()
        reader = user.id
        if chat is not None and chat.is_system and sysbot.is_support(m):
            reader = sysbot.get_bot(db).id   # человек видит «прочитано поддержкой»
        await manager.send_to_users(others, {"type": "read", "chat_id": chat_id,
                                             "user_id": reader})


@router.get("/{chat_id}/peer")
def peer_presence(chat_id: str, db: Session = Depends(get_db),
                  user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    _ensure_member(db, chat.id, user.id)
    peer = _peer(db, chat, user.id)
    if peer is None:
        return {"online": False, "last_seen": None}
    card = public_user(db, peer, user.id)
    online, seen = presence_of(db, peer, user.id)
    card.update({"online": online, "last_seen": seen.isoformat() if seen else None,
                 "blocked_by_me": is_blocked(db, user.id, peer.id)})
    if peer.is_bot and peer.bot_commands:
        import json
        try:
            card["commands"] = json.loads(peer.bot_commands)
        except Exception:
            card["commands"] = []
    return card


@router.delete("/{chat_id}/messages", status_code=204)
async def clear_history(chat_id: str, scope: str = "all", db: Session = Depends(get_db),
                        user: User = Depends(get_current_user)):
    """scope=me — очистить только у себя; all — у всех (в группах/каналах только админ)."""
    chat = _get_chat(db, chat_id)
    m = _ensure_member(db, chat.id, user.id)
    if chat.is_system and sysbot.is_support(m):
        scope = "me"   # админ не может стереть человеку его переписку с поддержкой
    if scope == "me":
        m.cleared_at = datetime.now(timezone.utc)
        db.commit()
        await manager.send_to_users([user.id], {"type": "cleared", "chat_id": chat_id})
        return
    if chat.type != "direct" and not _is_admin(m):
        raise HTTPException(status_code=403, detail="Очистить историю у всех может только админ")
    db.query(MessageReaction).filter(MessageReaction.chat_id == chat_id).delete()
    db.query(Message).filter(Message.chat_id == chat_id).delete()
    db.commit()
    await manager.send_to_users(member_ids(db, chat_id),
                                {"type": "cleared", "chat_id": chat_id})


def e2e_allowed(db: Session, chat: Chat) -> bool:
    """Сквозное шифрование — только в обычных личных чатах двух людей (не бот, не Connecto)."""
    if chat.type != "direct" or chat.is_system:
        return False
    users = db.query(User).filter(User.id.in_(member_ids(db, chat.id))).all()
    return len(users) == 2 and not any(u.is_bot for u in users)


def _check_envelope(enc: str) -> None:
    try:
        env = json.loads(enc)
        ok = (isinstance(env, dict) and env.get("v") == 1 and isinstance(env.get("c"), str)
              and isinstance(env.get("k"), dict) and 0 < len(env["k"]) <= 50)
    except Exception:
        ok = False
    if not ok:
        raise HTTPException(status_code=400, detail="Повреждённое зашифрованное сообщение")


def check_can_send(db: Session, chat: Chat, sender: User, kind: str) -> None:
    m = _ensure_member(db, chat.id, sender.id)
    if chat.type == "channel" and not _is_admin(m):
        raise HTTPException(status_code=403, detail="В канале публикуют только админы")
    if chat.type == "group" and not chat.members_can_send and not _is_admin(m):
        raise HTTPException(status_code=403, detail="Писать в группу могут только админы")
    if chat.is_system and sysbot.is_support(m):
        return   # админ отвечает в обращение от имени Connecto
    if chat.type == "direct":
        peer = _peer(db, chat, sender.id)
        if peer is None:
            raise HTTPException(status_code=403, detail="Собеседник удалил аккаунт")
        if is_blocked(db, peer.id, sender.id):
            raise HTTPException(status_code=403,
                                detail="Пользователь ограничил вам отправку сообщений")
        if is_blocked(db, sender.id, peer.id):
            raise HTTPException(status_code=403, detail="Вы заблокировали этого пользователя")
        if kind in ("voice", "round") and not allowed(db, peer, sender.id, "voice"):
            raise HTTPException(status_code=403,
                                detail="Пользователь ограничил голосовые и видеосообщения")
        if peer.is_bot and peer.bot_owner_id is not None and peer.banned:
            raise HTTPException(status_code=403, detail="Бот отключён")


@router.post("/{chat_id}/messages", status_code=201)
async def send_message(chat_id: str, data: MessageCreate, db: Session = Depends(get_db),
                       user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    check_can_send(db, chat, user, data.kind)
    enc = (data.enc or "").strip() or None
    if enc is not None:
        if not e2e_allowed(db, chat):
            raise HTTPException(status_code=400, detail="В этом чате шифрование недоступно")
        _check_envelope(enc)
    if data.kind == "text" and not data.text.strip() and enc is None:
        raise HTTPException(status_code=422, detail="Пустое сообщение")
    effect = (data.effect or "").strip() or None
    if effect:
        if effect not in FREE_EFFECTS | PREMIUM_EFFECTS:
            raise HTTPException(status_code=400, detail="Неизвестный эффект")
        if effect in PREMIUM_EFFECTS and not is_premium(user):
            raise HTTPException(status_code=403, detail="Этот эффект доступен с Connecto Premium")
    now = datetime.now(timezone.utc)
    open_at = None
    if data.open_at:
        from datetime import timedelta
        open_at = datetime.fromtimestamp(data.open_at / 1000, tz=timezone.utc)
        if open_at < now + timedelta(seconds=30):
            raise HTTPException(status_code=400, detail="Капсулу можно открыть не раньше чем через минуту")
        if open_at > now + timedelta(days=366 * 5):
            raise HTTPException(status_code=400, detail="Капсула — максимум на 5 лет")
    expires_at = None
    if chat.ttl_seconds:
        from datetime import timedelta
        expires_at = (open_at or now) + timedelta(seconds=chat.ttl_seconds)
    extra = None
    if data.story_id:
        from app.routers.stories import story_for_reply
        info = story_for_reply(db, data.story_id, user)
        if info["story"]["owner_id"] not in member_ids(db, chat_id):
            raise HTTPException(status_code=400, detail="Ответить на историю можно только автору")
        extra = json.dumps(info, ensure_ascii=False)
    author = user
    if chat.is_system:
        if sysbot.is_support(_member(db, chat_id, user.id)):
            author = sysbot.get_bot(db)   # ответ поддержки — от имени Connecto
            open_at = None
            extra = sysbot.SUPPORT_TAG
    msg = Message(chat_id=chat_id, sender_id=author.id, kind=data.kind,
                  text="" if enc else data.text, enc=enc,
                  media_url=data.media_url, file_name=data.file_name,
                  reply_to_id=data.reply_to_id, forwarded_from=data.forwarded_from,
                  effect=effect, silent=bool(data.silent), open_at=open_at,
                  expires_at=expires_at, extra=extra)
    db.add(msg)
    db.commit()
    db.refresh(msg)
    if chat.is_system and author is user:
        # человек написал в поддержку — обращение приходит в личку всем админам
        try:
            sysbot.sync_support(db, chat)
        except Exception:
            db.rollback()
    payload = await deliver(db, chat, msg, author)
    payload.pop("type", None)
    return payload


@router.patch("/{chat_id}/messages/{msg_id}")
async def edit_message(chat_id: str, msg_id: str, data: MessageEdit,
                       db: Session = Depends(get_db),
                       user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    mem = _ensure_member(db, chat_id, user.id)
    msg = db.query(Message).filter(Message.id == msg_id, Message.chat_id == chat_id).first()
    if msg is None:
        raise HTTPException(status_code=404, detail="Сообщение не найдено")
    own_support = (chat.is_system and sysbot.is_support(mem)
                   and msg.sender_id == sysbot.get_bot(db).id and sysbot.is_support_reply(msg))
    if msg.sender_id != user.id and not own_support:
        raise HTTPException(status_code=403, detail="Можно править только свои")
    if msg.kind != "text":
        raise HTTPException(status_code=400, detail="Можно править только текст")
    enc = (data.enc or "").strip() or None
    if enc is not None:
        if not e2e_allowed(db, chat):
            raise HTTPException(status_code=400, detail="В этом чате шифрование недоступно")
        _check_envelope(enc)
    elif not data.text.strip():
        raise HTTPException(status_code=422, detail="Пустое сообщение")
    msg.text = "" if enc else data.text
    msg.enc = enc
    msg.edited = True
    db.commit()
    db.refresh(msg)
    await manager.send_to_users(member_ids(db, chat_id), {
        "type": "edited", "chat_id": chat_id, "id": msg.id,
        "text": msg.text, "enc": msg.enc, "edited": True,
    })
    return _serialize(db, chat, [msg], user)[0]


@router.delete("/{chat_id}/messages/{msg_id}", status_code=204)
async def delete_message(chat_id: str, msg_id: str,
                         db: Session = Depends(get_db),
                         user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    member = _ensure_member(db, chat_id, user.id)
    msg = db.query(Message).filter(Message.id == msg_id, Message.chat_id == chat_id).first()
    if msg is None:
        return
    # в личке — любой из двоих; в группах/каналах — автор или админ
    if chat.type != "direct" and msg.sender_id != user.id and not _is_admin(member):
        raise HTTPException(status_code=403, detail="Нельзя удалить это сообщение")
    db.query(MessageReaction).filter(MessageReaction.message_id == msg_id).delete()
    db.delete(msg)
    db.commit()
    await manager.send_to_users(member_ids(db, chat_id), {
        "type": "msg_deleted", "chat_id": chat_id, "id": msg_id,
    })


@router.post("/{chat_id}/messages/{msg_id}/pin")
async def pin_message(chat_id: str, msg_id: str, data: PinUpdate,
                      db: Session = Depends(get_db),
                      user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    member = _ensure_member(db, chat_id, user.id)
    if chat.type != "direct" and not _is_admin(member):
        raise HTTPException(status_code=403, detail="Закреплять могут только админы")
    msg = db.query(Message).filter(Message.id == msg_id, Message.chat_id == chat_id).first()
    if msg is None:
        raise HTTPException(status_code=404, detail="Сообщение не найдено")
    if data.pinned:
        for m in db.query(Message).filter(Message.chat_id == chat_id,
                                           Message.pinned == True):  # noqa: E712
            m.pinned = False
    msg.pinned = data.pinned
    db.commit()
    db.refresh(msg)
    await manager.send_to_users(member_ids(db, chat_id), {
        "type": "pinned", "chat_id": chat_id, "id": msg.id, "pinned": data.pinned,
    })
    return _serialize(db, chat, [msg], user)[0]


class ReactIn(BaseModel):
    emoji: str = Field(min_length=1, max_length=16)


@router.post("/{chat_id}/messages/{msg_id}/react")
async def react(chat_id: str, msg_id: str, data: ReactIn, db: Session = Depends(get_db),
                user: User = Depends(get_current_user)):
    """Поставить/снять реакцию. Без Premium — одна на сообщение, с Premium — до трёх."""
    chat = _get_chat(db, chat_id)
    mem = _ensure_member(db, chat_id, user.id)
    msg = db.query(Message).filter(Message.id == msg_id, Message.chat_id == chat_id).first()
    if msg is None or msg.kind == "service":
        raise HTTPException(status_code=404, detail="Сообщение не найдено")
    if is_sealed(msg, user.id):
        raise HTTPException(status_code=400, detail="Капсула ещё не открыта")
    actor = user
    if chat.is_system and sysbot.is_support(mem):
        actor = sysbot.get_bot(db)   # реакция поддержки — от имени Connecto
    mine = (db.query(MessageReaction)
            .filter(MessageReaction.message_id == msg_id, MessageReaction.user_id == actor.id)
            .order_by(MessageReaction.created_at.asc()).all())
    same = next((r for r in mine if r.emoji == data.emoji), None)
    added = False
    if same is not None:
        db.delete(same)
    else:
        limit = 3 if is_premium(user) else 1
        while len(mine) >= limit:
            db.delete(mine.pop(0))
        db.add(MessageReaction(message_id=msg_id, chat_id=chat_id, user_id=actor.id,
                               emoji=data.emoji))
        added = True
    db.commit()
    reacts = reactions_for(db, [msg_id], None).get(msg_id, [])
    await manager.send_to_users(member_ids(db, chat_id), {
        "type": "reactions", "chat_id": chat_id, "id": msg_id, "reactions": reacts,
        "actor_id": actor.id, "actor_name": _name(actor), "emoji": data.emoji,
        "added": added, "author_id": msg.sender_id,
    })
    return {"reactions": reactions_for(db, [msg_id], actor.id).get(msg_id, [])}


# ── исчезающие сообщения ──

class TtlIn(BaseModel):
    seconds: int = 0


TTL_NAMES = {0: "выключил(а) автоудаление", 60: "включил(а) автоудаление: 1 минута",
             3600: "включил(а) автоудаление: 1 час", 86400: "включил(а) автоудаление: 1 день",
             604800: "включил(а) автоудаление: 1 неделя"}


@router.put("/{chat_id}/ttl")
async def set_ttl(chat_id: str, data: TtlIn, db: Session = Depends(get_db),
                  user: User = Depends(get_current_user)):
    chat = _get_chat(db, chat_id)
    m = _ensure_member(db, chat.id, user.id)
    if data.seconds not in TTL_VALUES:
        raise HTTPException(status_code=400, detail="Недопустимый срок")
    if chat.is_system:
        raise HTTPException(status_code=403, detail="В чате Connecto автоудаление недоступно")
    if chat.type != "direct" and not _is_admin(m):
        raise HTTPException(status_code=403, detail="Автоудаление меняют только админы")
    if (chat.ttl_seconds or 0) == data.seconds:
        return chat_out(db, chat, user, m)
    chat.ttl_seconds = data.seconds
    db.commit()
    msg = service_message(db, chat, user, f"{_name(user)} {TTL_NAMES[data.seconds]}")
    await deliver(db, chat, msg, user)
    await manager.send_to_users(member_ids(db, chat.id),
                                {"type": "chat_updated", "chat_id": chat.id})
    return chat_out(db, chat, user, m)
