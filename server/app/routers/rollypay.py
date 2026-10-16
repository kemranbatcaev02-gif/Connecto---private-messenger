"""Оплата через RollyPay (https://rollypay.io): СБП, карты РФ, крипта.

⚠️ ПОКА ВЫКЛЮЧЕНО. Код готов, но не подключён: сейчас покупка идёт через
«Написать в Connecto / Telegram». Как включить, когда заведёшь кассу:

1) В кабинете RollyPay создай кассу (терминал) и возьми:
   api_key, signing_secret (секрет для подписи вебхуков).
2) Рядом с сервером (/opt/connecto-server) создай файл rollypay.json:
   {
     "api_key": "rp_live_xxx",
     "signing_secret": "whsec_xxx",
     "terminal_id": "",                                        (можно пусто)
     "payment_method": "",                                     (пусто = выбор на странице оплаты; или "sbp")
     "success_url": "http://193.233.112.115:8000/pay/done",
     "fail_url": "http://193.233.112.115:8000/pay/done"
   }
3) В кабинете RollyPay укажи адрес вебхуков (callback_url):
   http://193.233.112.115:8000/pay/rollypay/webhook
4) В app/main.py раскомментируй строки с rollypay (подключение роутера),
   а в app/routers/economy.py → buy_coins — три строки с rollypay.
5) sudo systemctl restart connecto

Приложение менять не нужно: оно уже умеет открывать ссылку оплаты
(confirmation_url) и проверять статус платежа, когда возвращаешься из браузера.
Premium за рубли: POST /coins/premium/rub {"plan_id": "p1"} — в приложении
можно повесить на кнопку «Купить за ₽» вместо «Написать продавцу».

API (по SDK rollypay 0.1.4): база https://rollypay.io/api/v1, заголовок X-API-Key,
POST /payments {amount, order_id, payment_currency, description, customer_id,
success_redirect_url, fail_redirect_url, metadata} → {payment_id, pay_url}.
Вебхук: заголовки X-Timestamp и X-Signature = HMAC-SHA256("<timestamp>.<тело>",
signing_secret). Перед запуском сверь поля с docs.rollypay.io — сервис молодой.
"""
import hashlib
import hmac
import json
import os
import time
import urllib.request

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.deps import get_current_user, get_db
from app.models.social import Payment
from app.models.user import User

router = APIRouter(tags=["rollypay"])

RP_FILE = "rollypay.json"
RP_BASE = "https://rollypay.io/api/v1"
PAID = {"paid", "succeeded", "success", "completed"}
CANCELED = {"canceled", "cancelled", "expired", "failed"}


def rp_cfg() -> dict | None:
    try:
        if os.path.exists(RP_FILE):
            with open(RP_FILE, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            if cfg.get("api_key") and cfg.get("signing_secret"):
                return cfg
    except Exception:
        pass
    return None


def _rp(method: str, path: str, body: dict | None = None) -> dict:
    cfg = rp_cfg()
    if cfg is None:
        raise HTTPException(status_code=503, detail="Оплата не настроена")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{RP_BASE}/{path.lstrip('/')}", data=data, method=method,
        headers={"X-API-Key": cfg["api_key"], "Content-Type": "application/json",
                 "User-Agent": "connecto-server"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            out = json.loads(r.read().decode() or "{}")
    except Exception:
        raise HTTPException(status_code=502, detail="Платёжный сервис не ответил, попробуй позже")
    # некоторые ответы завёрнуты в {"data": {...}}
    return out.get("data") if isinstance(out.get("data"), dict) else out


def _status_of(obj: dict) -> str:
    return str(obj.get("status") or "").lower()


def _create(db: Session, me: User, pay: Payment, description: str) -> dict:
    from app.routers.economy import _pay_dict
    cfg = rp_cfg() or {}
    body = {
        "amount": f"{pay.rub}.00",
        "order_id": pay.id,
        "payment_currency": "RUB",
        "description": description,
        "customer_id": me.id,
        "metadata": {"payment_id": pay.id, "user_id": me.id, "package_id": pay.package_id},
    }
    if cfg.get("payment_method"):
        body["payment_method"] = cfg["payment_method"]
    if cfg.get("terminal_id"):
        body["terminal_id"] = cfg["terminal_id"]
    if cfg.get("success_url"):
        body["success_redirect_url"] = cfg["success_url"]
    if cfg.get("fail_url"):
        body["fail_redirect_url"] = cfg["fail_url"]
    obj = _rp("POST", "payments", body)
    pid = obj.get("payment_id") or obj.get("id")
    url = obj.get("pay_url") or obj.get("payment_url") or obj.get("url")
    if not pid or not url:
        pay.status = "canceled"
        db.commit()
        raise HTTPException(status_code=502, detail="Платёж не создан, попробуй ещё раз")
    pay.provider_id = f"rp:{pid}"
    pay.confirmation_url = url
    db.commit()
    return _pay_dict(pay)


def create_coins_payment(db: Session, me: User, pkg: dict) -> dict:
    pay = Payment(user_id=me.id, package_id=pkg["id"], coins=pkg["coins"], rub=pkg["rub"])
    db.add(pay)
    db.commit()
    db.refresh(pay)
    return _create(db, me, pay, f"Connecto: {pkg['coins']} коинов")


class PremiumRubIn(BaseModel):
    plan_id: str


@router.post("/coins/premium/rub")
def buy_premium_rub(data: PremiumRubIn, db: Session = Depends(get_db),
                    me: User = Depends(get_current_user)):
    from app.routers.economy import PREMIUM_PLANS
    plan = next((p for p in PREMIUM_PLANS if p["id"] == data.plan_id), None)
    if plan is None:
        raise HTTPException(status_code=404, detail="Тариф не найден")
    # coins=0 и package_id=p* — по ним _credit понимает, что это Premium
    pay = Payment(user_id=me.id, package_id=plan["id"], coins=0, rub=plan["rub"])
    db.add(pay)
    db.commit()
    db.refresh(pay)
    return _create(db, me, pay, f"Connecto Premium · {plan['title']}")


def _credit(db: Session, pay: Payment) -> None:
    """Зачислить покупку ровно один раз."""
    from app.routers.economy import PREMIUM_PLANS, _credit as credit_coins, _ws_me
    if pay.status == "succeeded":
        return
    plan = next((p for p in PREMIUM_PLANS if p["id"] == pay.package_id), None)
    if plan is None:
        credit_coins(db, pay)   # коины: там же пометка succeeded и уведомление
        return
    from app.routers.premium import grant
    user = db.query(User).filter(User.id == pay.user_id).first()
    if user is None:
        return
    won = (db.query(Payment).filter(Payment.id == pay.id, Payment.status == "pending")
           .update({"status": "succeeded"}, synchronize_session=False))
    if won != 1:   # уже зачислено параллельным запросом
        db.rollback()
        return
    pay.status = "succeeded"
    grant(user, plan["days"])
    db.commit()
    _ws_me([user.id])


def sync_payment(db: Session, pay: Payment) -> Payment:
    """Перепроверить платёж через API RollyPay (вебхуку на слово не верим)."""
    if pay.status != "pending" or not (pay.provider_id or "").startswith("rp:"):
        return pay
    obj = _rp("GET", f"payments/{pay.provider_id[3:]}")
    st = _status_of(obj)
    order = str(obj.get("order_id") or (obj.get("metadata") or {}).get("payment_id") or "")
    if st in PAID and order == pay.id and _amount_ok(obj, pay):
        _credit(db, pay)
    elif st in CANCELED:
        pay.status = "canceled"
        db.commit()
    return pay


def _amount_ok(obj: dict, pay: Payment) -> bool:
    """Оплачено столько, сколько просили, и в рублях."""
    cur = str(obj.get("payment_currency") or obj.get("currency") or "RUB").upper()
    try:
        amount = float(str(obj.get("amount", pay.rub)).replace(",", "."))
    except ValueError:
        return False
    return cur == "RUB" and amount + 0.01 >= pay.rub


def _check_signature(secret: str, ts: str, body: bytes, sig: str) -> bool:
    if not ts or not sig:
        return False
    try:
        t = float(ts)
        if t > 1e12:   # пришло в миллисекундах
            t /= 1000
        if abs(time.time() - t) > 600:   # старше 10 минут — повтор/подделка
            return False
    except ValueError:
        return False
    msg = ts.encode() + b"." + body
    good = hmac.new(secret.encode(), msg, hashlib.sha256).hexdigest()
    sig = sig.strip()
    if sig.startswith("sha256="):
        sig = sig[7:]
    return hmac.compare_digest(good, sig.lower())


@router.post("/pay/rollypay/webhook")
async def rp_webhook(request: Request):
    cfg = rp_cfg()
    raw = await request.body()
    if cfg is None or not _check_signature(cfg["signing_secret"],
                                           request.headers.get("X-Timestamp", ""),
                                           raw, request.headers.get("X-Signature", "")):
        raise HTTPException(status_code=401, detail="bad signature")
    try:
        body = json.loads(raw.decode() or "{}")
    except Exception:
        return {"ok": True}
    obj = body.get("data") if isinstance(body.get("data"), dict) else body
    obj = obj.get("payment") if isinstance(obj.get("payment"), dict) else obj
    pid = obj.get("payment_id") or obj.get("id")
    our = obj.get("order_id") or (obj.get("metadata") or {}).get("payment_id")
    if not pid or not our:
        return {"ok": True}
    from fastapi.concurrency import run_in_threadpool

    def work():
        db = SessionLocal()
        try:
            pay = (db.query(Payment)
                   .filter(Payment.id == our, Payment.provider_id == f"rp:{pid}").first())
            if pay is not None:
                sync_payment(db, pay)
        finally:
            db.close()
    try:
        await run_in_threadpool(work)
    except Exception:
        pass
    return {"ok": True}   # 2xx за 10 секунд, иначе RollyPay повторит
