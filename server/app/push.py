"""Отправка push-уведомлений через Firebase Cloud Messaging (HTTP v1).

Нужен файл сервис-аккаунта firebase.json рядом с сервером и пакеты:
    pip install google-auth requests
"""
import json
import logging
import os

logger = logging.getLogger("connecto")

SA_FILE = os.environ.get("FIREBASE_SA_FILE", "firebase.json")
if not os.path.exists(SA_FILE):
    alt = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "firebase.json")
    if os.path.exists(alt):
        SA_FILE = alt

PUBLIC_BASE = os.environ.get("PUBLIC_BASE", "https://connectomes.duckdns.org")
_SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]

_creds = None
_project_id = None
_ready = None  # None — не пробовали, True/False — результат


def _ensure():
    global _creds, _project_id, _ready
    if _ready is not None:
        return _ready
    try:
        from google.oauth2 import service_account  # noqa
        if not os.path.exists(SA_FILE):
            logger.warning("FCM: %s not found. Background pushes disabled.", SA_FILE)
            _ready = False
            return False
        _creds = service_account.Credentials.from_service_account_file(
            SA_FILE, scopes=_SCOPES)
        with open(SA_FILE, "r", encoding="utf-8") as f:
            _project_id = json.load(f).get("project_id")
        _ready = _project_id is not None
        if _ready:
            logger.info("FCM initialized successfully for project %s", _project_id)
    except Exception as e:
        logger.error("FCM init failed: %s", e)
        _ready = False
    return _ready


def _access_token():
    import google.auth.transport.requests
    if not _creds.valid:
        _creds.refresh(google.auth.transport.requests.Request())
    return _creds.token


def send_push(tokens, title, body, image=None, channel="messages", ttl=None, data=None):
    """Отправить уведомление на список FCM-токенов. Блокирующая — вызывать
    через run_in_threadpool. channel — канал уведомлений на телефоне
    (messages / calls_v2), ttl — сколько секунд уведомление актуально."""
    if not tokens or not _ensure():
        return
    try:
        import requests
        access = _access_token()
    except Exception as e:
        logger.warning("FCM auth error: %s", e)
        return
    url = f"https://fcm.googleapis.com/v1/projects/{_project_id}/messages:send"
    headers = {"Authorization": f"Bearer {access}",
               "Content-Type": "application/json"}
    img = None
    if image:
        img = image if image.startswith("http") else f"{PUBLIC_BASE}{image}"
    ch_id = "calls_v2" if channel in ("calls", "calls_v2") else channel
    for t in tokens:
        android_notif = {"channel_id": ch_id}
        if img:
            android_notif["image"] = img
        if data and "chat_id" in data and str(data["chat_id"]):
            android_notif["tag"] = f"chat_{data['chat_id']}"
        android = {
            "priority": "HIGH",
            "notification": android_notif,
        }
        if ttl:
            android["ttl"] = f"{int(ttl)}s"
        msg = {
            "message": {
                "token": t,
                "notification": {"title": title, "body": body},
                "android": android,
            }
        }
        if data:
            msg["message"]["data"] = {str(k): str(v) for k, v in data.items()}
        try:
            r = requests.post(url, headers=headers, json=msg, timeout=6)
            if r.status_code >= 400:
                logger.warning("FCM send failed %s: %s", r.status_code, r.text)
        except Exception as e:
            logger.warning("FCM post exception: %s", e)
