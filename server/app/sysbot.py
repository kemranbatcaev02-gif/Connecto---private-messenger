"""Системный бот «Connecto» — уведомления о входах, приветствие, поддержка.
Как служебный чат «Telegram»: с галочкой, в него же можно писать в поддержку."""
import json
import os
import secrets
from datetime import datetime, timezone

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.models.user import User
from app.models.chat import Chat, ChatMember, Message
from app.core.security import hash_password
from app.config import ADMIN_EMAILS, is_admin_email

SYSTEM_EMAIL = "system@connecto.local"

# Админы подключаются к чату «Connecto» человека как скрытые участники с этой ролью:
# у них обращение выглядит как обычная личка с этим человеком, а ответ уходит
# от имени Connecto (человек не видит, кто из админов ответил).
SUPPORT_ROLE = "support"
# ответы поддержки помечаются так (служебные уведомления Connecto — нет):
# админы видят в обращении только сообщения человека и ответы поддержки
SUPPORT_TAG = json.dumps({"support": True})
BACKFILL_MARK = "support_backfill.done"


def is_support_reply(msg: Message) -> bool:
    return bool(msg.extra) and '"support"' in (msg.extra or "")


def support_filter(q, bot_id: str):
    """Для админа в обращении: убрать служебные уведомления бота (входы, почта…)."""
    return q.filter(or_(Message.sender_id != bot_id, Message.extra.like('%"support"%')))


def get_bot(db: Session) -> User:
    bot = db.query(User).filter(User.email == SYSTEM_EMAIL).first()
    if bot is not None:
        return bot
    username = "connecto"
    if db.query(User).filter(User.username == username).first():
        username = "connecto_official"
    handle = username if not db.query(User).filter(User.handle == username).first() else None
    bot = User(username=username, handle=handle, email=SYSTEM_EMAIL,
               password_hash=hash_password(secrets.token_hex(24)),
               display_name="Connecto", bio="Служебные уведомления и поддержка",
               is_bot=True, is_verified=True)
    db.add(bot)
    db.commit()
    db.refresh(bot)
    return bot


def system_chat(db: Session, user: User) -> Chat:
    bot = get_bot(db)
    # чаты поддержки других людей (где я — админ-помощник) не считаются «моими»
    mine = db.query(ChatMember.chat_id).filter(ChatMember.user_id == user.id,
                                               ChatMember.role != SUPPORT_ROLE)
    row = (db.query(Chat).join(ChatMember, ChatMember.chat_id == Chat.id)
           .filter(Chat.is_system == True, ChatMember.user_id == bot.id,  # noqa: E712
                   Chat.id.in_(mine)).first())
    if row is not None:
        return row
    chat = Chat(type="direct", title=None, is_system=True)
    db.add(chat)
    db.flush()
    db.add(ChatMember(chat_id=chat.id, user_id=bot.id, role="member"))
    db.add(ChatMember(chat_id=chat.id, user_id=user.id, role="member"))
    db.commit()
    db.refresh(chat)
    return chat


# ── поддержка: обращения приходят админам в личку ──

def admin_users(db: Session) -> list[User]:
    emails = [e.strip().lower() for e in ADMIN_EMAILS]
    return [u for u in db.query(User).filter(func.lower(User.email).in_(emails)).all()
            if not u.banned and not u.is_bot]


def support_owner(db: Session, chat: Chat) -> User | None:
    """Человек, которому принадлежит чат «Connecto» (не бот и не админ-помощник)."""
    bot = get_bot(db)
    for m in db.query(ChatMember).filter(ChatMember.chat_id == chat.id):
        if m.user_id != bot.id and m.role != SUPPORT_ROLE:
            return db.query(User).filter(User.id == m.user_id).first()
    return None


def is_support(mem: ChatMember | None) -> bool:
    return mem is not None and mem.role == SUPPORT_ROLE


def sync_support(db: Session, chat: Chat) -> None:
    """Подключить к обращению всех текущих админов и убрать тех, кто больше не админ."""
    if not chat.is_system:
        return
    owner = support_owner(db, chat)
    if owner is None:
        return
    rows = {m.user_id: m for m in db.query(ChatMember).filter(ChatMember.chat_id == chat.id)}
    changed = False
    for m in rows.values():
        if m.role == SUPPORT_ROLE:
            u = db.query(User).filter(User.id == m.user_id).first()
            if u is None or not is_admin_email(u.email) or u.banned:
                db.delete(m)
                changed = True
    admins = [a for a in admin_users(db) if a.id != owner.id and a.id not in rows]
    if admins:
        # «вступил» чуть раньше последнего сообщения человека — оно будет непрочитанным
        last = (db.query(Message).filter(Message.chat_id == chat.id,
                                         Message.sender_id == owner.id)
                .order_by(Message.created_at.desc()).first())
        from datetime import timedelta
        joined = (last.created_at - timedelta(seconds=1)) if last and last.created_at else None
        for a in admins:
            m = ChatMember(chat_id=chat.id, user_id=a.id, role=SUPPORT_ROLE)
            if joined is not None:
                m.joined_at = joined
            db.add(m)
        changed = True
    if changed:
        db.commit()


def backfill_support(db: Session, days: int = 30) -> None:
    """Один раз после обновления: старые обращения (человек писал в «Connecto»
    недавно) — тоже в личку админам. Дальше — только когда человек пишет."""
    from datetime import timedelta
    if os.path.exists(BACKFILL_MARK):
        return
    bot = get_bot(db)
    since = datetime.now(timezone.utc) - timedelta(days=days)
    ids = {cid for (cid,) in db.query(Message.chat_id)
           .join(Chat, Chat.id == Message.chat_id)
           .filter(Chat.is_system == True, Message.sender_id != bot.id,  # noqa: E712
                   Message.created_at > since).distinct()}
    for chat in db.query(Chat).filter(Chat.id.in_(ids)).all() if ids else []:
        try:
            sync_support(db, chat)
        except Exception:
            db.rollback()
    try:
        with open(BACKFILL_MARK, "w") as f:
            f.write(datetime.now(timezone.utc).isoformat())
    except OSError:
        pass


def post(db: Session, user: User, text: str, sync: bool = True) -> Message:
    """Написать пользователю от имени Connecto (и доставить в реальном времени)."""
    from app.messaging import deliver_sync
    bot = get_bot(db)
    chat = system_chat(db, user)
    msg = Message(chat_id=chat.id, sender_id=bot.id, kind="text", text=text)
    db.add(msg)
    db.commit()
    db.refresh(msg)
    if sync:
        deliver_sync(db, chat, msg, bot)
    return msg


def login_alert_text(platform: str, city: str) -> str:
    now = datetime.now(timezone.utc).strftime("%d.%m.%Y %H:%M UTC")
    lines = ["🔐 Новый вход в аккаунт", ""]
    lines.append(f"Устройство: {platform or 'неизвестно'}")
    if city:
        lines.append(f"Место: {city} (примерно)")
    lines.append(f"Время: {now}")
    lines += ["", "Если это были не вы — откройте Настройки → Устройства и "
                  "завершите этот сеанс, затем смените пароль."]
    return "\n".join(lines)


WELCOME = ("👋 Добро пожаловать в Connecto!\n\n"
           "Здесь будут приходить уведомления о входах в аккаунт и ответы поддержки. "
           "Если что-то не работает или есть идея — просто напишите сюда.")
