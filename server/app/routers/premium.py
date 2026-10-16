"""Connecto Premium: статус, возможности, активация промокода."""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.deps import get_db, get_current_user
from app.models.user import User
from app.models.chat import PromoCode, PromoUse
from app.privacy import is_premium, as_utc
from app.users_out import me_dict

router = APIRouter(prefix="/premium", tags=["premium"])

# что даёт Premium (показывается в приложении; всё проверяется на сервере/в клиенте)
PERKS = [
    {"icon": "star", "title": "Значок Premium", "text": "Звезда рядом с именем в чатах и профиле"},
    {"icon": "stories", "title": "Истории без ограничений", "text": "Вместо 2 в неделю, срок от 6 до 48 часов"},
    {"icon": "stealth", "title": "Режим инкогнито", "text": "Смотри истории так, чтобы автор не узнал"},
    {"icon": "coins", "title": "Двойной ежедневный бонус", "text": "Вдвое больше коинов каждый день"},
    {"icon": "gift", "title": "Подарки самому себе", "text": "Покупай любые подарки в свою коллекцию"},
    {"icon": "heart", "title": "3 реакции на сообщение", "text": "Вместо одной"},
    {"icon": "upload", "title": "Файлы до 500 МБ", "text": "Вместо 100 МБ"},
    {"icon": "users", "title": "До 6 аккаунтов", "text": "Вместо 3 в одном приложении"},
    {"icon": "pin", "title": "До 10 закреплённых чатов", "text": "Вместо 5"},
    {"icon": "bot", "title": "До 20 ботов", "text": "Вместо 5"},
    {"icon": "text", "title": "Описание до 300 символов", "text": "Вместо 140"},
    {"icon": "palette", "title": "Эксклюзивные цвета и обои", "text": "Дополнительные акценты и фоны чатов"},
    {"icon": "layers", "title": "Премиум-темы", "text": "Полночь, Океан, Лес, Закат, Сакура, Киберпанк, Мокка"},
    {"icon": "bubble", "title": "Стили сообщений", "text": "Стекло, Неон и переливающееся Сияние"},
    {"icon": "type", "title": "6 дополнительных шрифтов", "text": "От строгого Montserrat до рукописного Caveat"},
    {"icon": "transition", "title": "Анимации переходов", "text": "Зум, Глубина и Подъём с пружиной"},
    {"icon": "waves", "title": "Живые обои", "text": "Плавно переливающиеся фоны чатов"},
    {"icon": "cover", "title": "Видео-обложка профиля", "text": "Короткое видео до 15 секунд вместо фото"},
    {"icon": "emoji", "title": "Эмодзи-статус", "text": "Эмодзи рядом с именем — видят все"},
    {"icon": "ring", "title": "Рамки аватара", "text": "Радуга, Золото и Сияние в профиле"},
    {"icon": "appicon", "title": "Иконки приложения",
     "text": "Неон, Золото, Стекло, Космос, Сакура, Лава и Аврора на рабочем столе"},
    {"icon": "frame", "title": "Рамки чатов и обводка сообщений",
     "text": "Неон, Сияние, Золото, Стекло и своя рамка с ручной настройкой"},
    {"icon": "nav", "title": "Стили нижнего меню", "text": "Капсула и Неон"},
    {"icon": "icons", "title": "Стили иконок", "text": "Неоновые и переливающиеся иконки меню"},
    {"icon": "effects", "title": "Премиум-эффекты сообщений",
     "text": "Салют, Деньги, Молния, Радуга, Звездопад и Сакура на весь экран"},
    {"icon": "stealth", "title": "Невидимка",
     "text": "Собеседники не видят, что ты печатаешь или записываешь голосовое"},
]


def grant(user: User, days: int) -> None:
    now = datetime.now(timezone.utc)
    base = as_utc(user.premium_until)
    start = base if base and base > now else now
    user.premium_until = start + timedelta(days=days)


@router.get("")
def premium_status(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    pu = as_utc(user.premium_until)
    return {"active": is_premium(user),
            "until": pu.isoformat() if pu else None,
            "perks": PERKS}


class RedeemIn(BaseModel):
    code: str


@router.post("/redeem")
def redeem(data: RedeemIn, db: Session = Depends(get_db),
           user: User = Depends(get_current_user)):
    code = data.code.strip().upper()
    promo = db.query(PromoCode).filter(PromoCode.code == code).first()
    if promo is None or promo.uses_left <= 0:
        raise HTTPException(status_code=404, detail="Промокод не найден или закончился")
    if db.query(PromoUse).filter(PromoUse.code == code, PromoUse.user_id == user.id).first():
        raise HTTPException(status_code=400, detail="Ты уже активировал этот промокод")
    if promo.days:
        grant(user, promo.days)
    if getattr(promo, "coins", 0):
        from app.routers.economy import add_coins
        add_coins(db, user, int(promo.coins), "promo", f"Промокод {code}")
    promo.uses_left -= 1
    db.add(PromoUse(code=code, user_id=user.id))
    db.commit()
    out = me_dict(db, user)
    out["promo_days"] = int(promo.days or 0)
    out["promo_coins"] = int(getattr(promo, "coins", 0) or 0)
    return out
