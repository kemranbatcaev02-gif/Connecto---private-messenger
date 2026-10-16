"""Ключи для сквозного шифрования личных чатов.

Каждое устройство создаёт пару X25519, закрытую часть хранит у себя, а сюда
присылает только открытую. Отправитель шифрует сообщение случайным ключом и
«заворачивает» этот ключ для каждого устройства собеседника и своих устройств.
Сервер хранит только конверт и прочитать его не может.
"""
import base64

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.deps import get_db, get_current_user
from app.models.user import User
from app.models.chat import Chat, ChatMember, DeviceKey
from app.messaging import member_ids

router = APIRouter(tags=["e2e"])


class KeyIn(BaseModel):
    device_id: str = Field(min_length=1, max_length=64)
    public_key: str = Field(min_length=40, max_length=64)   # base64 от 32 байт


def _key_ok(b64: str) -> bool:
    try:
        return len(base64.b64decode(b64, validate=True)) == 32
    except Exception:
        return False


@router.put("/keys")
def register_key(data: KeyIn, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    if not _key_ok(data.public_key):
        raise HTTPException(status_code=400, detail="Неверный ключ")
    rows = db.query(DeviceKey).filter(DeviceKey.user_id == user.id,
                                      DeviceKey.device_id == data.device_id).all()
    same = next((r for r in rows if r.public_key == data.public_key), None)
    for r in rows:
        r.active = r is same
    if same is None:
        same = DeviceKey(user_id=user.id, device_id=data.device_id,
                         public_key=data.public_key, active=True)
        db.add(same)
    # не больше 10 активных устройств — самые старые выключаем
    active = (db.query(DeviceKey).filter(DeviceKey.user_id == user.id, DeviceKey.active == True)  # noqa: E712
              .order_by(DeviceKey.created_at.desc()).all())
    for old in active[10:]:
        if old is not same:
            old.active = False
    db.commit()
    db.refresh(same)
    return {"key_id": same.id}


@router.get("/chats/{chat_id}/keys")
def chat_keys(chat_id: str, db: Session = Depends(get_db),
              user: User = Depends(get_current_user)):
    from app.routers.chats import e2e_allowed
    chat = db.query(Chat).filter(Chat.id == chat_id).first()
    if chat is None:
        raise HTTPException(status_code=404, detail="Чат не найден")
    if db.query(ChatMember).filter(ChatMember.chat_id == chat.id,
                                   ChatMember.user_id == user.id).first() is None:
        raise HTTPException(status_code=403, detail="Нет доступа к этому чату")
    if not e2e_allowed(db, chat):
        return {"enabled": False, "keys": []}
    ids = member_ids(db, chat.id)
    rows = db.query(DeviceKey).filter(DeviceKey.user_id.in_(ids),
                                      DeviceKey.active == True).all()  # noqa: E712
    return {"enabled": True,
            "keys": [{"user_id": r.user_id, "key_id": r.id, "public_key": r.public_key}
                     for r in rows]}
