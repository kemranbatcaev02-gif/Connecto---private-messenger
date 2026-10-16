"""Полный прогон сервера Connecto: сценарии как у живых пользователей."""
import os
import sys
import tempfile

TMP = tempfile.mkdtemp()
os.chdir(TMP)
os.environ["DATABASE_URL"] = f"sqlite:///{TMP}/test.db"
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402
from app import email_service, verify  # noqa: E402

SENT = {}


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def H(tok):
    return {"Authorization": f"Bearer {tok}"}


def register(c, name, email, dev):
    r = c.post("/auth/register", json={"username": name, "email": email, "password": "password123",
                                       "display_name": name.capitalize(), "device_id": dev,
                                       "platform": "Android"})
    assert r.status_code == 201, r.text
    return r.json()


def set_handle(c, tok, h):
    r = c.post("/users/handle", json={"handle": h}, headers=H(tok))
    assert r.status_code == 200, r.text


@pytest.fixture(scope="module")
def users(client):
    a = register(client, "alice", "kemranbatcaev02@gmail.com", "devA")   # админ
    b = register(client, "bob", "bob@x.ru", "devB")
    c = register(client, "carl", "carl@x.ru", "devC")
    for u, h in ((a, "alice"), (b, "bobby"), (c, "carlito")):
        set_handle(client, u["access_token"], h)
    return {"a": a, "b": b, "c": c}


def tok(users, k):
    return users[k]["access_token"]


def uid(users, k):
    return users[k]["user"]["id"]


# ── регистрация, приветствие, вход ──

def test_register_and_welcome(client, users):
    me = client.get("/me", headers=H(tok(users, "a"))).json()
    assert me["is_admin"] is True and me["is_premium"] is False
    assert me["privacy"]["phone"] == "contacts"
    chats = client.get("/chats", headers=H(tok(users, "b"))).json()
    sysc = [c for c in chats if c["is_system"]]
    assert len(sysc) == 1 and sysc[0]["is_verified"] and sysc[0]["title"] == "Connecto"
    assert "Добро пожаловать" in sysc[0]["last_message"]
    assert sysc[0]["unread_count"] == 1


def test_login_trusted_device_no_code(client, users):
    r = client.post("/auth/login", json={"login": "bob", "password": "password123",
                                         "device_id": "devB", "platform": "Android"})
    assert r.status_code == 200 and "access_token" in r.json()


def test_login_new_device_with_email_code(client, users, monkeypatch):
    monkeypatch.setattr(email_service, "enabled", lambda: True)
    monkeypatch.setattr(email_service, "send_login_code",
                        lambda email, code, city, plat: SENT.update(login=code) or True)
    r = client.post("/auth/login", json={"login": "bob@x.ru", "password": "password123",
                                         "device_id": "devB2", "platform": "Windows"})
    assert r.json()["needs_code"] is True
    # неверный код
    r2 = client.post("/auth/login/verify", json={"login": "bob", "password": "password123",
                                                 "code": "000000", "device_id": "devB2"})
    assert r2.status_code == 400
    r3 = client.post("/auth/login/verify", json={"login": "bob", "password": "password123",
                                                 "code": SENT["login"], "device_id": "devB2",
                                                 "platform": "Windows"})
    assert r3.status_code == 200, r3.text
    # бот Connecto прислал уведомление о новом входе
    chats = client.get("/chats", headers=H(r3.json()["access_token"])).json()
    sysc = next(c for c in chats if c["is_system"])
    assert "Новый вход" in sysc["last_message"]


def test_code_attempt_limit():
    verify.gen_and_store("x:test")
    for _ in range(5):
        assert not verify.check("x:test", "999999x")
    assert "x:test" not in verify._pending


def test_wrong_password_and_rate_limit(client):
    for _ in range(10):
        r = client.post("/auth/login", json={"login": "ghost", "password": "nope"})
        assert r.status_code == 401
    r = client.post("/auth/login", json={"login": "ghost", "password": "nope"})
    assert r.status_code == 429


# ── облачный пароль ──

def test_cloud_password_flow(client, users, monkeypatch):
    t = tok(users, "c")
    r = client.put("/me/cloud_password", json={"new": "cloudpw1", "hint": "кот"}, headers=H(t))
    assert r.json()["has_cloud_password"] is True
    # сменить без текущего — нельзя
    assert client.put("/me/cloud_password", json={"new": "x12345"}, headers=H(t)).status_code == 400
    r = client.post("/auth/login", json={"login": "carl", "password": "password123",
                                         "device_id": "devC2", "platform": "iOS"})
    d = r.json()
    assert d["needs_password"] is True and d["hint"] == "кот"
    assert client.post("/auth/login/2fa", json={"ticket": d["ticket"], "password": "bad"}).status_code == 401
    r2 = client.post("/auth/login/2fa", json={"ticket": d["ticket"], "password": "cloudpw1"})
    assert r2.status_code == 200 and "access_token" in r2.json()
    # забыл облачный пароль → код на почту → отключить
    monkeypatch.setattr(email_service, "send_2fa_reset_code",
                        lambda email, code: SENT.update(r2fa=code) or True)
    r = client.post("/auth/login", json={"login": "carl", "password": "password123",
                                         "device_id": "devC3"})
    ticket = r.json()["ticket"]
    assert client.post("/auth/login/2fa/forgot", json={"ticket": ticket}).json()["sent"]
    r3 = client.post("/auth/login/2fa/reset", json={"ticket": ticket, "code": SENT["r2fa"]})
    assert r3.status_code == 200
    assert client.get("/me", headers=H(t)).json()["has_cloud_password"] is False


# ── сеансы ──

def test_sessions_refresh_and_terminate(client, users):
    r = client.post("/auth/login", json={"login": "alice", "password": "password123",
                                         "device_id": "devA2", "platform": "Linux"})
    second = r.json()
    t1 = tok(users, "a")
    sess = client.get("/sessions", headers=H(t1)).json()
    assert len(sess) >= 2 and sum(1 for s in sess if s["current"]) == 1
    # refresh
    rr = client.post("/auth/refresh", json={"refresh_token": second["refresh_token"]})
    assert rr.status_code == 200
    # завершить остальные с первого устройства
    assert client.delete("/sessions", headers=H(t1)).status_code == 204
    assert client.get("/me", headers=H(second["access_token"])).status_code == 401
    assert client.post("/auth/refresh", json={"refresh_token": second["refresh_token"]}).status_code == 401
    assert client.get("/me", headers=H(t1)).status_code == 200
    # устройство больше не доверенное — снова нужен код/вход
    assert len(client.get("/sessions", headers=H(t1)).json()) == 1


def test_password_change_and_reset(client, users, monkeypatch):
    r = client.post("/auth/login", json={"login": "bob", "password": "password123",
                                         "device_id": "devB", "platform": "Android"})
    other = r.json()["access_token"]
    t = tok(users, "b")
    # сеанс devB пересоздан логином → старый токен того же устройства умер
    assert client.get("/me", headers=H(t)).status_code == 401
    assert client.post("/me/password", json={"old_password": "bad", "new_password": "newpass123"},
                       headers=H(other)).status_code == 400
    assert client.post("/me/password", json={"old_password": "password123",
                                             "new_password": "newpass123"},
                       headers=H(other)).json()["ok"]
    monkeypatch.setattr(email_service, "send_reset_code",
                        lambda email, code: SENT.update(reset=code) or True)
    assert client.post("/auth/password/forgot", json={"email": "bob@x.ru"}).json()["sent"]
    assert client.post("/auth/password/reset", json={"email": "bob@x.ru", "code": SENT["reset"],
                                                     "new_password": "password123"}).json()["ok"]
    # после сброса — везде вышли
    assert client.get("/me", headers=H(other)).status_code == 401
    r = client.post("/auth/login", json={"login": "bob", "password": "password123",
                                         "device_id": "devB", "platform": "Android"})
    users["b"] = r.json()


# ── личные чаты, блокировки, приватность ──

@pytest.fixture(scope="module")
def direct(client, users):
    r = client.post("/chats", json={"type": "direct", "member_ids": [uid(users, "b")]},
                    headers=H(tok(users, "a")))
    assert r.status_code == 201, r.text
    again = client.post("/chats", json={"type": "direct", "member_ids": [uid(users, "b")]},
                        headers=H(tok(users, "a"))).json()
    assert again["id"] == r.json()["id"]
    return r.json()["id"]


def test_direct_send_and_unread(client, users, direct):
    r = client.post(f"/chats/{direct}/messages", json={"text": "Привет, Боб"},
                    headers=H(tok(users, "a")))
    assert r.status_code == 201 and r.json()["sender_name"] == "Alice"
    chats = client.get("/chats", headers=H(tok(users, "b"))).json()
    d = next(c for c in chats if c["id"] == direct)
    assert d["unread_count"] == 1 and d["title"] == "Alice" and d["peer_id"] == uid(users, "a")
    client.post(f"/chats/{direct}/read", headers=H(tok(users, "b")))
    d = next(c for c in client.get("/chats", headers=H(tok(users, "b"))).json() if c["id"] == direct)
    assert d["unread_count"] == 0
    msgs = client.get(f"/chats/{direct}/messages", headers=H(tok(users, "a"))).json()
    assert msgs[-1]["read"] is True
    # профиль собеседника знает наш личный чат (кнопка «Звук» в профиле)
    prof = client.get(f"/users/{uid(users, 'b')}", headers=H(tok(users, "a"))).json()
    assert prof["chat_id"] == direct


def test_delete_for_me_keeps_chat(client, users, direct):
    a, b = tok(users, "a"), tok(users, "b")
    cid = direct
    client.post(f"/chats/{cid}/messages", json={"text": "до удаления"}, headers=H(a))
    r = client.delete(f"/chats/{cid}?scope=me", headers=H(b))
    assert r.status_code == 204
    # у bob чат пропал из списка и история пустая
    assert cid not in [c["id"] for c in client.get("/chats", headers=H(b)).json()]
    assert client.get(f"/chats/{cid}/messages", headers=H(b)).json() == []
    # alice по-прежнему может писать — bob получает новое сообщение
    r = client.post(f"/chats/{cid}/messages", json={"text": "снова привет"}, headers=H(a))
    assert r.status_code == 201, r.text
    lst = client.get("/chats", headers=H(b)).json()
    mine = [c for c in lst if c["id"] == cid]
    assert mine and mine[0]["last_message"] == "снова привет" and mine[0]["unread_count"] == 1
    msgs = client.get(f"/chats/{cid}/messages", headers=H(b)).json()
    assert [m["text"] for m in msgs] == ["снова привет"]
    # у alice история на месте
    assert len(client.get(f"/chats/{cid}/messages", headers=H(a)).json()) >= 2
    # очистка «у себя»
    r = client.delete(f"/chats/{cid}/messages?scope=me", headers=H(a))
    assert r.status_code == 204
    assert client.get(f"/chats/{cid}/messages", headers=H(a)).json() == []
    assert len(client.get(f"/chats/{cid}/messages", headers=H(b)).json()) == 1


def test_effects_capsule_ttl(client, users, direct):
    import time as _t
    from datetime import datetime, timedelta, timezone
    a, b = tok(users, "a"), tok(users, "b")
    cid = direct
    # эффект: бесплатный — можно, премиальный без Premium — нельзя
    r = client.post(f"/chats/{cid}/messages", json={"text": "ура", "effect": "confetti",
                                                   "silent": True}, headers=H(b))
    assert r.status_code == 201 and r.json()["effect"] == "confetti" and r.json()["silent"] is True
    assert client.post(f"/chats/{cid}/messages", json={"text": "x", "effect": "money"},
                       headers=H(b)).status_code == 403
    assert client.post(f"/chats/{cid}/messages", json={"text": "x", "effect": "nope"},
                       headers=H(b)).status_code == 400
    # капсула времени
    open_ms = int((_t.time() + 3600) * 1000)
    r = client.post(f"/chats/{cid}/messages", json={"text": "секрет", "open_at": open_ms},
                    headers=H(a))
    assert r.status_code == 201 and r.json()["text"] == "секрет"
    mid = r.json()["id"]
    theirs = [m for m in client.get(f"/chats/{cid}/messages", headers=H(b)).json() if m["id"] == mid][0]
    assert theirs["sealed"] is True and theirs["text"] == ""
    mine = [m for m in client.get(f"/chats/{cid}/messages", headers=H(a)).json() if m["id"] == mid][0]
    assert mine["sealed"] is False and mine["text"] == "секрет"
    lst = client.get("/chats", headers=H(b)).json()
    assert [c for c in lst if c["id"] == cid][0]["last_message"] == "📦 Капсула времени"
    assert client.post(f"/chats/{cid}/messages/{mid}/react", json={"emoji": "👍"},
                       headers=H(b)).status_code == 400
    assert client.post(f"/chats/{cid}/messages", json={"text": "x", "open_at": int(_t.time() * 1000)},
                       headers=H(a)).status_code == 400
    # открываем капсулу «вручную» — сдвигаем время в базе
    from app.database import SessionLocal
    from app.models.chat import Message
    db = SessionLocal()
    m = db.query(Message).filter(Message.id == mid).first()
    m.open_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()
    db.close()
    theirs = [m for m in client.get(f"/chats/{cid}/messages", headers=H(b)).json() if m["id"] == mid][0]
    assert theirs["sealed"] is False and theirs["text"] == "секрет"
    # автоудаление
    assert client.put(f"/chats/{cid}/ttl", json={"seconds": 5}, headers=H(a)).status_code == 400
    r = client.put(f"/chats/{cid}/ttl", json={"seconds": 60}, headers=H(a))
    assert r.status_code == 200 and r.json()["ttl_seconds"] == 60
    r = client.post(f"/chats/{cid}/messages", json={"text": "исчезну"}, headers=H(a))
    eid = r.json()["id"]
    assert r.json()["expires_at"] is not None
    db = SessionLocal()
    m = db.query(Message).filter(Message.id == eid).first()
    m.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()
    assert all(x["id"] != eid for x in client.get(f"/chats/{cid}/messages", headers=H(b)).json())
    import asyncio
    from app.messaging import purge_expired
    assert asyncio.run(purge_expired(db)) >= 1
    assert db.query(Message).filter(Message.id == eid).first() is None
    db.close()
    client.put(f"/chats/{cid}/ttl", json={"seconds": 0}, headers=H(a))


def test_block_prevents_messages(client, users, direct):
    tb = tok(users, "b")
    client.post(f"/users/{uid(users, 'a')}/block", headers=H(tb))
    r = client.post(f"/chats/{direct}/messages", json={"text": "эй"}, headers=H(tok(users, "a")))
    assert r.status_code == 403
    assert client.post(f"/chats/{direct}/messages", json={"text": "эй"},
                       headers=H(tb)).status_code == 403
    blocks = client.get("/users/blocks", headers=H(tb)).json()
    assert blocks[0]["id"] == uid(users, "a")
    client.delete(f"/users/{uid(users, 'a')}/block", headers=H(tb))
    assert client.post(f"/chats/{direct}/messages", json={"text": "снова"},
                       headers=H(tok(users, "a"))).status_code == 201


def test_privacy_enforced(client, users, direct):
    tb = tok(users, "b")
    client.patch("/me", json={"phone": "+79990001122", "avatar_url": "/media/b.png",
                              "birthday": "2000-01-01"}, headers=H(tb))
    r = client.put("/me/privacy", json={"values": {"phone": "contacts", "avatar": "none",
                                                   "voice": "none", "lastseen": "contacts"}},
                   headers=H(tb))
    assert r.json()["privacy"]["avatar"] == "none"
    pa = client.get(f"/users/{uid(users, 'b')}", headers=H(tok(users, "a"))).json()
    pc = client.get(f"/users/{uid(users, 'b')}", headers=H(tok(users, "c"))).json()
    assert pa["phone"] == "+79990001122"          # контакт — видит
    assert pc["phone"] is None                   # не контакт — нет
    assert pa["avatar_url"] is None and pc["avatar_url"] is None
    assert pc["birthday"] is None
    # голосовые запрещены
    r = client.post(f"/chats/{direct}/messages", json={"kind": "voice", "media_url": "/media/v.m4a"},
                    headers=H(tok(users, "a")))
    assert r.status_code == 403
    client.put("/me/privacy", json={"values": {"voice": "all", "avatar": "all"}}, headers=H(tb))


def test_read_receipts_off(client, users, direct):
    tb = tok(users, "b")
    client.put("/me/privacy", json={"read_receipts": False}, headers=H(tb))
    m = client.post(f"/chats/{direct}/messages", json={"text": "прочитаешь?"},
                    headers=H(tok(users, "a"))).json()
    client.post(f"/chats/{direct}/read", headers=H(tb))
    msgs = client.get(f"/chats/{direct}/messages", headers=H(tok(users, "a"))).json()
    assert next(x for x in msgs if x["id"] == m["id"])["read"] is False
    client.put("/me/privacy", json={"read_receipts": True}, headers=H(tb))


def test_reactions_free_and_premium(client, users, direct):
    m = client.post(f"/chats/{direct}/messages", json={"text": "лайкни"},
                    headers=H(tok(users, "a"))).json()
    tb = tok(users, "b")
    url = f"/chats/{direct}/messages/{m['id']}/react"
    client.post(url, json={"emoji": "❤️"}, headers=H(tb))
    r = client.post(url, json={"emoji": "👍"}, headers=H(tb)).json()
    assert [x["emoji"] for x in r["reactions"]] == ["👍"]          # без Premium — одна
    client.post(f"/admin/users/{uid(users, 'b')}/premium", json={"days": 30},
                headers=H(tok(users, "a")))
    for e in ("❤️", "🔥", "😂"):
        r = client.post(url, json={"emoji": e}, headers=H(tb)).json()
    assert len(r["reactions"]) == 3                               # с Premium — до трёх
    r = client.post(url, json={"emoji": "😂"}, headers=H(tb)).json()   # повтор — снять
    assert len(r["reactions"]) == 2
    msgs = client.get(f"/chats/{direct}/messages", headers=H(tok(users, "a"))).json()
    assert len(next(x for x in msgs if x["id"] == m["id"])["reactions"]) == 2


def test_edit_delete_pin_direct(client, users, direct):
    ta, tb = tok(users, "a"), tok(users, "b")
    m = client.post(f"/chats/{direct}/messages", json={"text": "опечатка"}, headers=H(ta)).json()
    assert client.patch(f"/chats/{direct}/messages/{m['id']}", json={"text": "исправлено"},
                        headers=H(tb)).status_code == 403
    assert client.patch(f"/chats/{direct}/messages/{m['id']}", json={"text": "исправлено"},
                        headers=H(ta)).json()["edited"] is True
    assert client.post(f"/chats/{direct}/messages/{m['id']}/pin", json={"pinned": True},
                       headers=H(tb)).json()["pinned"] is True
    assert client.delete(f"/chats/{direct}/messages/{m['id']}", headers=H(tb)).status_code == 204


# ── группы ──

@pytest.fixture(scope="module")
def group(client, users):
    tc = tok(users, "c")
    client.put("/me/privacy", json={"values": {"invites": "none"}}, headers=H(tc))
    r = client.post("/chats", json={"type": "group", "title": "Зал",
                                    "member_ids": [uid(users, "b"), uid(users, "c")]},
                    headers=H(tok(users, "a")))
    assert r.status_code == 201, r.text
    d = r.json()
    assert d["my_role"] == "owner" and d["member_count"] == 2
    assert d["skipped"][0]["id"] == uid(users, "c")               # C запретил приглашения
    assert d["invite_link"].endswith(d["invite_link"].split("/j/")[1])
    return d


def test_group_messages_and_permissions(client, users, group):
    gid = group["id"]
    ta, tb = tok(users, "a"), tok(users, "b")
    msgs = client.get(f"/chats/{gid}/messages", headers=H(tb)).json()
    assert msgs[0]["kind"] == "service" and "создал(а) группу" in msgs[0]["text"]
    assert client.post(f"/chats/{gid}/messages", json={"text": "всем привет"},
                       headers=H(tb)).status_code == 201
    client.patch(f"/chats/{gid}", json={"members_can_send": False}, headers=H(ta))
    assert client.post(f"/chats/{gid}/messages", json={"text": "можно?"},
                       headers=H(tb)).status_code == 403
    assert client.patch(f"/chats/{gid}", json={"title": "x"}, headers=H(tb)).status_code == 403
    # назначить админом
    assert client.patch(f"/chats/{gid}/members/{uid(users, 'b')}", json={"role": "admin"},
                        headers=H(tb)).status_code == 403
    assert client.patch(f"/chats/{gid}/members/{uid(users, 'b')}", json={"role": "admin"},
                        headers=H(ta)).json()["role"] == "admin"
    assert client.post(f"/chats/{gid}/messages", json={"text": "теперь можно"},
                       headers=H(tb)).status_code == 201
    info = client.get(f"/chats/{gid}", headers=H(tb)).json()
    assert info["my_role"] == "admin" and info["invite_link"]
    members = client.get(f"/chats/{gid}/members", headers=H(tb)).json()
    assert [m["role"] for m in members] == ["owner", "admin"]
    # переименование → сервисное сообщение
    client.patch(f"/chats/{gid}", json={"title": "Качалка", "description": "Жмём от груди"},
                 headers=H(tb))
    info = client.get(f"/chats/{gid}", headers=H(ta)).json()
    assert info["title"] == "Качалка" and info["description"] == "Жмём от груди"
    last = client.get(f"/chats/{gid}/messages", headers=H(ta)).json()[-1]
    assert last["kind"] == "service" and "Качалка" in last["text"]


def test_group_invite_kick_ban(client, users, group):
    gid = group["id"]
    ta, tc = tok(users, "a"), tok(users, "c")
    code = client.post(f"/chats/{gid}/invite", headers=H(ta)).json()["invite_code"]
    prev = client.get(f"/join/{code}", headers=H(tc)).json()
    assert prev["is_member"] is False and prev["title"] == "Качалка"
    assert client.post(f"/join/{code}", headers=H(tc)).json()["is_member"] is True
    page = client.get(f"/j/{code}")
    assert page.status_code == 200 and "Качалка" in page.text
    # C не админ — не может кикать
    assert client.delete(f"/chats/{gid}/members/{uid(users, 'b')}", headers=H(tc)).status_code == 403
    assert client.delete(f"/chats/{gid}/members/{uid(users, 'c')}", headers=H(ta)).status_code == 204
    assert client.post(f"/join/{code}", headers=H(tc)).status_code == 403   # забанен
    bans = client.get(f"/chats/{gid}/bans", headers=H(ta)).json()
    assert bans[0]["id"] == uid(users, "c")
    client.delete(f"/chats/{gid}/bans/{uid(users, 'c')}", headers=H(ta))
    assert client.post(f"/join/{code}", headers=H(tc)).status_code == 200
    # админ не может кикнуть владельца
    assert client.delete(f"/chats/{gid}/members/{uid(users, 'a')}",
                         headers=H(tok(users, "b"))).status_code == 403


def test_owner_leaves_transfers_ownership(client, users, group):
    gid = group["id"]
    ta = tok(users, "a")
    assert client.delete(f"/chats/{gid}?scope=both", headers=H(tok(users, "b"))).status_code == 403
    client.post(f"/chats/{gid}/leave", headers=H(ta))
    info = client.get(f"/chats/{gid}", headers=H(tok(users, "b"))).json()
    assert info["my_role"] == "owner"
    last = client.get(f"/chats/{gid}/messages", headers=H(tok(users, "b"))).json()[-1]
    assert "покинул(а)" in last["text"]
    assert client.delete(f"/chats/{gid}?scope=both", headers=H(tok(users, "b"))).status_code == 204
    assert client.get(f"/chats/{gid}", headers=H(tok(users, "b"))).status_code == 404


# ── каналы ──

def test_channel_flow(client, users):
    ta, tb, tc = tok(users, "a"), tok(users, "b"), tok(users, "c")
    r = client.post("/chats", json={"type": "channel", "title": "Новости Connecto",
                                    "description": "Обновления", "handle": "connectonews"},
                    headers=H(ta))
    assert r.status_code == 201, r.text
    ch = r.json()
    # занятая ссылка
    assert client.post("/chats", json={"type": "channel", "title": "x", "handle": "connectonews"},
                       headers=H(ta)).status_code == 409
    assert client.post("/chats", json={"type": "channel", "title": "x", "handle": "alice"},
                       headers=H(ta)).status_code == 409   # совпадает с юзернеймом
    found = client.get("/chats/public/search?q=connectonews", headers=H(tb)).json()
    assert found[0]["id"] == ch["id"] and found[0]["is_member"] is False
    # предпросмотр публичного канала без вступления
    client.post(f"/chats/{ch['id']}/messages", json={"text": "Первый пост"}, headers=H(ta))
    posts = client.get(f"/chats/{ch['id']}/messages", headers=H(tb)).json()
    assert posts[-1]["text"] == "Первый пост" and posts[-1]["sender_name"] == "Новости Connecto"
    assert client.post(f"/chats/{ch['id']}/join", headers=H(tb)).json()["is_member"] is True
    assert client.post(f"/chats/{ch['id']}/messages", json={"text": "я тоже"},
                       headers=H(tb)).status_code == 403
    assert client.get(f"/chats/{ch['id']}/members", headers=H(tb)).status_code == 403
    assert client.get(f"/chats/{ch['id']}/members", headers=H(ta)).status_code == 200
    # подписчик ставит реакцию
    pid = posts[-1]["id"]
    assert client.post(f"/chats/{ch['id']}/messages/{pid}/react", json={"emoji": "🔥"},
                       headers=H(tb)).status_code == 200
    # приватный канал без ссылки — вступить нельзя
    priv = client.post("/chats", json={"type": "channel", "title": "Секрет"}, headers=H(ta)).json()
    assert client.post(f"/chats/{priv['id']}/join", headers=H(tc)).status_code == 403
    assert client.get(f"/chats/{priv['id']}/messages", headers=H(tc)).status_code == 403
    # мьют
    assert client.put(f"/chats/{ch['id']}/mute", json={"until": -1},
                      headers=H(tb)).json()["muted_until"] == -1


# ── боты ──

def test_bots_full(client, users):
    ta, tb = tok(users, "a"), tok(users, "b")
    assert client.post("/bots", json={"name": "Эхо", "username": "echo"},
                       headers=H(ta)).status_code == 400   # не заканчивается на bot
    r = client.post("/bots", json={"name": "Эхо", "username": "echo_bot"}, headers=H(ta))
    assert r.status_code == 201, r.text
    bot = r.json()
    token = bot["token"]
    api = f"/bot{token}"
    me = client.get(f"{api}/getMe").json()
    assert me["ok"] and me["result"]["username"] == "echo_bot"
    assert client.get("/botBAD:TOKEN/getMe").status_code == 401
    client.post(f"{api}/setMyCommands", json={"commands": [
        {"command": "/start", "description": "Начать"}, {"command": "help", "description": "Помощь"}]})
    # пользователь находит бота и пишет ему
    found = client.get("/users/search?q=echo", headers=H(tb)).json()
    assert found[0]["is_bot"] is True
    chat = client.post("/chats", json={"type": "direct", "member_ids": [bot["id"]]},
                       headers=H(tb)).json()
    assert chat["peer_is_bot"] is True
    peer = client.get(f"/chats/{chat['id']}/peer", headers=H(tb)).json()
    assert [c["command"] for c in peer["commands"]] == ["start", "help"]
    client.post(f"/chats/{chat['id']}/messages", json={"text": "/start"}, headers=H(tb))
    ups = client.get(f"{api}/getUpdates").json()["result"]
    assert len(ups) == 1 and ups[0]["message"]["text"] == "/start"
    assert ups[0]["message"]["from"]["username"] == "bobby"
    off = ups[0]["update_id"] + 1
    reply = client.post(f"{api}/sendMessage", json={"chat_id": chat["id"], "text": "Привет! Я эхо."})
    assert reply.json()["ok"]
    msgs = client.get(f"/chats/{chat['id']}/messages", headers=H(tb)).json()
    assert msgs[-1]["text"] == "Привет! Я эхо." and msgs[-1]["sender_is_bot"] is True
    # подтверждение offset и long-poll с таймаутом
    assert client.get(f"{api}/getUpdates", params={"offset": off, "timeout": 1}).json()["result"] == []
    # правка/удаление своего
    mid = reply.json()["result"]["message_id"]
    assert client.post(f"{api}/editMessageText", json={"chat_id": chat["id"], "message_id": mid,
                                                       "text": "Эхо v2"}).json()["ok"]
    assert client.post(f"{api}/deleteMessage", json={"chat_id": chat["id"],
                                                     "message_id": mid}).json()["ok"]
    # бот в группе без админки видит только команды
    g = client.post("/chats", json={"type": "group", "title": "С ботом",
                                    "member_ids": [bot["id"]]}, headers=H(ta)).json()
    client.post(f"/chats/{g['id']}/messages", json={"text": "обычный текст"}, headers=H(ta))
    client.post(f"/chats/{g['id']}/messages", json={"text": "/help@echo_bot"}, headers=H(ta))
    ups = client.get(f"{api}/getUpdates", params={"offset": off}).json()["result"]
    assert [u["message"]["text"] for u in ups] == ["/help@echo_bot"]
    # чужой чат — нельзя
    other = client.post("/chats", json={"type": "group", "title": "Без бота"}, headers=H(tb)).json()
    assert client.post(f"{api}/sendMessage", json={"chat_id": other["id"], "text": "x"}).status_code == 403
    # новый токен — старый умер
    new = client.post(f"/bots/{bot['id']}/token", headers=H(ta)).json()["token"]
    assert client.get(f"{api}/getMe").status_code == 401
    assert client.get(f"/bot{new}/getMe").json()["ok"]
    # вебхук
    assert client.post(f"/bot{new}/setWebhook", json={"url": "https://example.com/hook"}).json()["ok"]
    assert client.get(f"/bot{new}/getWebhookInfo").json()["result"]["url"] == "https://example.com/hook"
    client.post(f"/bot{new}/deleteWebhook")
    # редактирование и удаление
    e = client.patch(f"/bots/{bot['id']}", json={"bio": "Повторяю за вами"}, headers=H(ta)).json()
    assert e["bio"] == "Повторяю за вами"
    assert len(client.get("/bots", headers=H(ta)).json()) == 1
    assert client.delete(f"/bots/{bot['id']}", headers=H(tb)).status_code == 404
    assert client.delete(f"/bots/{bot['id']}", headers=H(ta)).status_code == 204
    assert client.get(f"/bot{new}/getMe").status_code == 401


# ── премиум, админка, поддержка ──

def test_premium_promo_admin(client, users):
    ta, tc = tok(users, "a"), tok(users, "c")
    assert client.get("/admin/stats", headers=H(tc)).status_code == 403
    st = client.get("/admin/stats", headers=H(ta)).json()
    assert st["users"] == 3 and st["premium"] >= 1
    p = client.post("/admin/promo", json={"days": 7, "uses": 2}, headers=H(ta)).json()
    r = client.post("/premium/redeem", json={"code": p["code"].lower()}, headers=H(tc))
    assert r.status_code == 200 and r.json()["is_premium"] is True
    assert client.post("/premium/redeem", json={"code": p["code"]}, headers=H(tc)).status_code == 400
    assert client.get("/premium", headers=H(tc)).json()["active"] is True
    assert client.get("/admin/promo", headers=H(ta)).json()[0]["uses_left"] == 1
    # снять премиум
    client.post(f"/admin/users/{uid(users, 'c')}/premium", json={"days": 0}, headers=H(ta))
    assert client.get("/me", headers=H(tc)).json()["is_premium"] is False
    # длинное описание без премиума
    assert client.patch("/me", json={"bio": "x" * 200}, headers=H(tc)).status_code == 400


def test_cover_emoji_and_admin_tools(client, users):
    ta, tc = tok(users, "a"), tok(users, "c")
    c_id = uid(users, "c")
    # фото-обложка — всем
    r = client.patch("/me", json={"cover_url": "/uploads/c.jpg", "cover_kind": "image"}, headers=H(tc))
    assert r.status_code == 200 and r.json()["cover_url"] == "/uploads/c.jpg"
    # видео-обложка и эмодзи-статус — только Premium
    assert client.patch("/me", json={"cover_url": "/u/v.mp4", "cover_kind": "video"},
                        headers=H(tc)).status_code == 403
    assert client.patch("/me", json={"emoji_status": "🔥"}, headers=H(tc)).status_code == 403
    # админ выдаёт Premium себе и другому
    a_id = uid(users, "a")
    assert client.post(f"/admin/users/{a_id}/premium", json={"days": 30},
                       headers=H(ta)).json()["is_premium"] is True
    client.post(f"/admin/users/{c_id}/premium", json={"days": 30}, headers=H(ta))
    r = client.patch("/me", json={"cover_url": "/u/v.mp4", "cover_kind": "video",
                                  "emoji_status": "🔥"}, headers=H(tc))
    assert r.status_code == 200 and r.json()["cover_kind"] == "video" and r.json()["emoji_status"] == "🔥"
    prof = client.get(f"/users/{c_id}", headers=H(ta)).json()
    assert prof["emoji_status"] == "🔥" and prof["cover_kind"] == "video"
    # Premium сняли — видео-обложка и статус скрываются
    client.post(f"/admin/users/{c_id}/premium", json={"days": 0}, headers=H(ta))
    prof = client.get(f"/users/{c_id}", headers=H(ta)).json()
    assert prof["emoji_status"] is None and prof["cover_url"] is None
    # статистика по дням, карточка, галочка, сообщение, выход
    st = client.get("/admin/stats", headers=H(ta)).json()
    assert len(st["daily_users"]) == 14 and st["daily_users"][-1]["count"] >= 3
    d = client.get(f"/admin/users/{c_id}", headers=H(ta)).json()
    assert "sessions" in d and d["messages"] >= 0
    assert client.post(f"/admin/users/{c_id}/verify", json={"value": True},
                       headers=H(ta)).json()["is_verified"] is True
    assert client.get(f"/users/{c_id}", headers=H(ta)).json()["is_verified"] is True
    assert client.post(f"/admin/users/{c_id}/message", json={"text": "Привет от админа"},
                       headers=H(ta)).status_code == 200
    assert any(p["id"] == a_id for p in client.get("/admin/premium", headers=H(ta)).json())
    chats = client.get("/admin/chats", headers=H(ta)).json()
    assert isinstance(chats, list)
    if chats:
        cid = chats[0]["id"]
        assert client.post(f"/admin/chats/{cid}/verify", json={"value": True},
                           headers=H(ta)).json()["is_verified"] is True
    assert client.post(f"/admin/users/{c_id}/logout", headers=H(ta)).status_code == 200
    assert client.get("/me", headers=H(tc)).status_code == 401
    # вернуть carl в строй для следующих тестов
    r = client.post("/auth/login", json={"login": "carl", "password": "password123",
                                          "device_id": "devC", "platform": "Android"})
    users["c"]["access_token"] = r.json()["access_token"]


def test_reports_and_support(client, users):
    ta, tc = tok(users, "a"), tok(users, "c")
    client.post("/report", json={"target_id": uid(users, "b"), "reason": "спам"}, headers=H(tc))
    reps = client.get("/admin/reports", headers=H(ta)).json()
    assert reps[0]["reason"] == "спам" and reps[0]["target_name"] == "Bob"
    sysc = next(c for c in client.get("/chats", headers=H(tc)).json() if c["is_system"])
    client.post(f"/chats/{sysc['id']}/messages", json={"text": "Не приходит код"}, headers=H(tc))
    sup = client.get("/admin/support", headers=H(ta)).json()
    item = next(s for s in sup if s["chat_id"] == sysc["id"])
    assert item["waiting"] is True and item["last_text"] == "Не приходит код"
    client.post(f"/admin/support/{sysc['id']}", json={"text": "Проверь спам 🙂"}, headers=H(ta))
    msgs = client.get(f"/chats/{sysc['id']}/messages", headers=H(tc)).json()
    assert msgs[-1]["text"] == "Проверь спам 🙂" and msgs[-1]["sender_verified"] is True
    assert client.post("/admin/broadcast", json={"text": "Вышло обновление!"},
                       headers=H(ta)).json()["sent"] == 3


def test_admin_ban_kills_sessions(client, users):
    ta = tok(users, "a")
    r = client.post("/auth/login", json={"login": "carl", "password": "password123",
                                         "device_id": "devC", "platform": "Android"})
    tc = r.json()["access_token"]
    client.post(f"/admin/users/{uid(users, 'c')}/ban", headers=H(ta))
    assert client.get("/me", headers=H(tc)).status_code == 401
    assert client.post("/auth/login", json={"login": "carl", "password": "password123",
                                            "device_id": "devC"}).status_code == 403
    client.post(f"/admin/users/{uid(users, 'c')}/unban", headers=H(ta))
    r = client.post("/auth/login", json={"login": "carl", "password": "password123",
                                         "device_id": "devC", "platform": "Android"})
    users["c"] = r.json()


# ── загрузка файлов ──

def test_upload_limits(client, users, monkeypatch):
    from app.routers import upload
    t = tok(users, "c")
    r = client.post("/upload", files={"file": ("a.txt", b"hello", "text/plain")}, headers=H(t))
    assert r.status_code == 200 and r.json()["size"] == 5
    monkeypatch.setattr(upload, "FREE_LIMIT", 3)
    r = client.post("/upload", files={"file": ("a.txt", b"hello", "text/plain")}, headers=H(t))
    assert r.status_code == 413


# ── WebSocket ──

def test_websocket_delivery(client, users, direct):
    ta, tb = tok(users, "a"), tok(users, "b")
    with client.websocket_connect(f"/ws?token={tb}") as ws:
        client.post(f"/chats/{direct}/messages", json={"text": "в реальном времени"}, headers=H(ta))
        ev = ws.receive_json()
        assert ev["type"] == "message" and ev["text"] == "в реальном времени"
        assert ev["sender_name"] == "Alice" and ev["chat_type"] == "direct"
        with client.websocket_connect(f"/ws?token={ta}") as wa:
            wa.send_json({"type": "typing", "chat_id": direct, "state": "typing"})
            ev = ws.receive_json()
            assert ev["type"] == "typing" and ev["name"] == "Alice"
    with pytest.raises(Exception):
        with client.websocket_connect("/ws?token=bad") as ws:
            ws.receive_json()


# ── регистрация с кодом и смена почты ──

def test_register_requires_email_code(client, monkeypatch):
    monkeypatch.setattr(email_service, "enabled", lambda: True)
    monkeypatch.setattr(email_service, "send_code",
                        lambda email, code: SENT.update(reg=code) or True)
    body = {"username": "dora", "email": "Dora@X.ru", "password": "password123",
            "display_name": "Dora", "device_id": "devD", "platform": "Android"}
    # без кода — нельзя
    assert client.post("/auth/register", json=body).status_code == 400
    # занятый логин / почта — сразу 409 на шаге кода
    assert client.post("/auth/register/code",
                       json={"email": "bob@x.ru", "username": "zzz"}).status_code == 409
    r = client.post("/auth/register/code", json={"email": "dora@x.ru", "username": "dora"})
    assert r.status_code == 200 and r.json()["required"] is True
    bad = dict(body, code="000000")
    assert client.post("/auth/register", json=bad).status_code == 400
    ok = dict(body, code=SENT["reg"])
    r = client.post("/auth/register", json=ok)
    assert r.status_code == 201, r.text
    assert r.json()["user"]["email"] == "dora@x.ru"


def test_change_email(client, users, monkeypatch):
    tc = tok(users, "c")
    # неверный пароль
    r = client.post("/me/email", json={"new_email": "carl2@x.ru", "password": "nope"}, headers=H(tc))
    assert r.status_code == 400
    # чужая почта
    r = client.post("/me/email", json={"new_email": "bob@x.ru", "password": "password123"},
                    headers=H(tc))
    assert r.status_code == 409
    monkeypatch.setattr(email_service, "enabled", lambda: True)
    monkeypatch.setattr(email_service, "send_email_change_code",
                        lambda email, code: SENT.update(chmail=code) or True)
    monkeypatch.setattr(email_service, "send_email_changed_notice", lambda e, m: True)
    r = client.post("/me/email", json={"new_email": "Carl2@x.ru", "password": "password123"},
                    headers=H(tc))
    assert r.status_code == 200 and r.json()["sent"] is True
    assert client.post("/me/email/confirm", json={"new_email": "carl2@x.ru", "code": "111111"},
                       headers=H(tc)).status_code == 400
    r = client.post("/me/email/confirm", json={"new_email": "carl2@x.ru", "code": SENT["chmail"]},
                    headers=H(tc))
    assert r.status_code == 200 and r.json()["email"] == "carl2@x.ru"
    # вход по новой почте
    r = client.post("/auth/login", json={"login": "carl2@x.ru", "password": "password123",
                                         "device_id": "devC"})
    assert r.status_code == 200
    users["c"] = r.json()   # вход с того же устройства заменил сеанс


# ── истории ──

def test_stories_limits_views_posts(client, users, direct):
    ta, tb, tc = tok(users, "a"), tok(users, "b"), tok(users, "c")
    a_id = uid(users, "a")
    client.post(f"/admin/users/{a_id}/premium", json={"days": 0}, headers=H(ta))
    st = {"media_url": "/media/s1.jpg", "kind": "image", "caption": "Привет"}
    r1 = client.post("/stories", json=st, headers=H(ta))
    assert r1.status_code == 201, r1.text
    assert r1.json()["limits"]["left"] == 1
    # срок без Premium выбирать нельзя
    assert client.post("/stories", json=dict(st, hours=6), headers=H(ta)).status_code == 403
    r2 = client.post("/stories", json=dict(st, pinned=True, audience="contacts"), headers=H(ta))
    assert r2.status_code == 201
    # третья в неделю — нельзя
    r3 = client.post("/stories", json=st, headers=H(ta))
    assert r3.status_code == 403 and "Premium" in r3.json()["detail"]
    s1, s2 = r1.json()["id"], r2.json()["id"]
    # Боб — собеседник, видит обе истории в ленте
    feed = client.get("/stories", headers=H(tb)).json()["groups"]
    g = next(x for x in feed if x["user"]["id"] == a_id)
    assert len(g["stories"]) == 2 and g["has_unseen"] is True
    # Карл не собеседник: ленты нет, но профильные «для всех» видны, «для контактов» — нет
    assert all(x["user"]["id"] != a_id for x in client.get("/stories", headers=H(tc)).json()["groups"])
    us = client.get(f"/stories/user/{a_id}", headers=H(tc)).json()["stories"]
    assert [s["id"] for s in us] == [s1]
    assert client.get(f"/users/{a_id}/posts", headers=H(tc)).json() == []
    assert [p["id"] for p in client.get(f"/users/{a_id}/posts", headers=H(tb)).json()] == [s2]
    # просмотр и реакция
    assert client.post(f"/stories/{s1}/view", headers=H(tb)).status_code == 200
    assert client.post(f"/stories/{s1}/react", json={"emoji": "🔥"}, headers=H(tb)).status_code == 200
    assert client.post(f"/stories/{s1}/react", json={"emoji": "💩"}, headers=H(tb)).status_code == 400
    feed = client.get("/stories", headers=H(tb)).json()["groups"]
    g = next(x for x in feed if x["user"]["id"] == a_id)
    assert [s["seen"] for s in g["stories"]] == [True, False]
    viewers = client.get(f"/stories/{s1}/viewers", headers=H(ta)).json()
    assert viewers[0]["user"]["id"] == uid(users, "b") and viewers[0]["reaction"] == "🔥"
    assert client.get(f"/stories/{s1}/viewers", headers=H(tb)).status_code == 403
    mine = client.get("/stories", headers=H(ta)).json()["groups"][0]
    assert mine["is_me"] and mine["stories"][0]["views_count"] == 1
    # профиль показывает счётчики
    prof = client.get(f"/users/{a_id}", headers=H(tb)).json()
    assert prof["has_stories"] is True and prof["posts_count"] == 1
    # ответ на историю приходит в личку с превью
    r = client.post(f"/chats/{direct}/messages", json={"text": "класс!", "story_id": s1},
                    headers=H(tb))
    assert r.status_code == 201 and r.json()["extra"]["story"]["id"] == s1
    # закреп / удаление
    assert client.put(f"/stories/{s1}/pin", json={"pinned": True}, headers=H(tb)).status_code == 403
    assert client.put(f"/stories/{s1}/pin", json={"pinned": True}, headers=H(ta)).json()["pinned"]
    assert client.delete(f"/stories/{s1}", headers=H(ta)).status_code == 204
    assert client.post(f"/stories/{s1}/view", headers=H(tb)).status_code == 404
    # удаление не возвращает лимит (всё ещё 0 из 2)
    assert client.get("/stories/limits", headers=H(ta)).json()["left"] == 0
    # блокировка скрывает истории
    client.post(f"/users/{uid(users, 'b')}/block", headers=H(ta))
    assert client.get(f"/stories/user/{a_id}", headers=H(tb)).json()["stories"] == []
    client.delete(f"/users/{uid(users, 'b')}/block", headers=H(ta))


def test_stories_premium(client, users):
    ta, tc = tok(users, "a"), tok(users, "c")
    client.post(f"/admin/users/{uid(users, 'c')}/premium", json={"days": 30}, headers=H(ta))
    for _ in range(3):
        r = client.post("/stories", json={"media_url": "/media/v.mp4", "kind": "video",
                                          "hours": 6}, headers=H(tc))
        assert r.status_code == 201, r.text
    lim = client.get("/stories/limits", headers=H(tc)).json()
    assert lim["premium"] is True and lim["used"] == 3
    # инкогнито: просмотр не записан
    sid = r.json()["id"]
    client.post(f"/stories/{sid}/view?stealth=true", headers=H(tc))
    client.post(f"/admin/users/{uid(users, 'c')}/premium", json={"days": 0}, headers=H(ta))


# ── коины, подарки, Premium за коины ──

def test_coins_daily_and_admin(client, users):
    ta, tc = tok(users, "a"), tok(users, "c")
    w = client.get("/coins", headers=H(tc)).json()
    assert w["balance"] == 0 and w["daily"]["available"] is True
    assert w["packages"][0] == {"id": "c100", "coins": 100, "rub": 49, "discount": 0,
                                "popular": False}
    assert w["packages"][-1]["discount"] > 10 and w["payments_enabled"] is False
    r = client.post("/coins/daily", headers=H(tc))
    assert r.status_code == 200 and r.json()["reward"] == 1
    assert client.post("/coins/daily", headers=H(tc)).status_code == 400
    # покупка без настроенной оплаты
    assert client.post("/coins/buy", json={"package_id": "c100"}, headers=H(tc)).status_code == 503
    # админ начисляет, обычный пользователь — нет
    assert client.post(f"/admin/users/{uid(users, 'c')}/coins", json={"amount": 5000},
                       headers=H(tc)).status_code == 403
    r = client.post(f"/admin/users/{uid(users, 'c')}/coins", json={"amount": 5000},
                    headers=H(ta))
    assert r.json()["coins"] == 5001
    # промокод на коины
    p = client.post("/admin/promo", json={"coins": 50, "uses": 1}, headers=H(ta)).json()
    r = client.post("/premium/redeem", json={"code": p["code"]}, headers=H(tc)).json()
    assert r["coins"] == 5051 and r["promo_coins"] == 50
    hist = client.get("/coins/history", headers=H(tc)).json()
    assert [h["kind"] for h in hist][:3] == ["promo", "admin", "daily"]


def test_gifts_flow(client, users, direct):
    ta, tb, tc = tok(users, "a"), tok(users, "b"), tok(users, "c")
    b_id = uid(users, "b")
    cat = client.get("/gifts/catalog", headers=H(tc)).json()["gifts"]
    assert len(cat) == 15 and cat[-1]["rarity"] == "legendary" and cat[-1]["left"] == 100
    # у Алисы коинов нет
    r = client.post("/gifts/send", json={"to_user_id": b_id, "gift_id": "rose"}, headers=H(ta))
    assert r.status_code == 402
    # Карл дарит розу и дракона (лимитированный, №1)
    r = client.post("/gifts/send", json={"to_user_id": b_id, "gift_id": "rose",
                                         "text": "Тебе!"}, headers=H(tc))
    assert r.status_code == 201, r.text
    r2 = client.post("/gifts/send", json={"to_user_id": b_id, "gift_id": "dragon",
                                          "anonymous": True}, headers=H(tc))
    assert r2.status_code == 201 and r2.json()["gift"]["serial"] == 1
    assert r2.json()["balance"] == 5051 - 15 - 2500
    cat = client.get("/gifts/catalog", headers=H(tc)).json()["gifts"]
    assert cat[-1]["left"] == 99
    # в профиле Боба: дракон первым (дороже), отправитель анонимного скрыт от других
    g = client.get(f"/users/{b_id}/gifts", headers=H(ta)).json()
    assert g["count"] == 2 and g["gifts"][0]["gift"]["id"] == "dragon"
    assert g["gifts"][0]["from"] is None and g["gifts"][1]["from"]["id"] == uid(users, "c")
    # сам Боб видит, кто подарил анонимно
    own = client.get(f"/users/{b_id}/gifts", headers=H(tb)).json()
    assert own["gifts"][0]["from"]["id"] == uid(users, "c")
    # подарок пришёл сообщением в личку от Карла
    chats = client.get("/chats", headers=H(tb)).json()
    assert any(c["last_message"] == "🎁 Подарок" for c in chats)
    # скрыть и обменять
    rose = own["gifts"][1]["id"]
    assert client.put(f"/gifts/{rose}/hide", json={"hidden": True}, headers=H(tb)).json()["hidden"]
    assert client.get(f"/users/{b_id}/gifts", headers=H(ta)).json()["count"] == 1
    assert client.post(f"/gifts/{rose}/convert", headers=H(ta)).status_code == 404
    r = client.post(f"/gifts/{rose}/convert", headers=H(tb)).json()
    assert r["coins"] == 10 and r["balance"] == 10
    assert client.get(f"/users/{b_id}", headers=H(ta)).json()["gifts_count"] == 1
    # приватность подарков
    client.put("/me/privacy", json={"values": {"gifts": "none"}}, headers=H(tb))
    assert client.get(f"/users/{b_id}/gifts", headers=H(ta)).json()["gifts"] == []
    client.put("/me/privacy", json={"values": {"gifts": "all"}}, headers=H(tb))


def test_premium_for_coins(client, users):
    ta, tc = tok(users, "a"), tok(users, "c")
    bal = client.get("/coins", headers=H(tc)).json()["balance"]
    # подарить Premium Алисе на месяц
    r = client.post("/coins/premium", json={"plan_id": "p1", "to_user_id": uid(users, "a")},
                    headers=H(tc))
    assert r.status_code == 200 and r.json()["coins"] == bal - 299
    assert client.get("/me", headers=H(ta)).json()["is_premium"] is True
    # на год не хватает
    assert client.post("/coins/premium", json={"plan_id": "p12"}, headers=H(tc)).status_code == 402
    client.post(f"/admin/users/{uid(users, 'a')}/premium", json={"days": 0}, headers=H(ta))


def test_coins_purchase_yookassa(client, users, monkeypatch):
    from app.routers import economy
    tb = tok(users, "b")
    monkeypatch.setattr(economy, "yk_cfg", lambda: {"shop_id": "1", "secret_key": "k",
                                                    "return_url": "http://x/pay/done"})
    state = {}

    def fake(method, path, body=None, idem=None):
        if method == "POST":
            state["meta"] = body["metadata"]
            assert body["amount"]["value"] == "439.00"
            return {"id": "yk-1", "status": "pending",
                    "confirmation": {"confirmation_url": "https://pay/yk-1"}}
        return {"id": "yk-1", "status": state.get("st", "pending"), "metadata": state["meta"]}
    monkeypatch.setattr(economy, "_yk_request", fake)
    before = client.get("/coins", headers=H(tb)).json()["balance"]
    p = client.post("/coins/buy", json={"package_id": "c1000"}, headers=H(tb)).json()
    assert p["confirmation_url"] == "https://pay/yk-1" and p["status"] == "pending"
    assert client.get(f"/coins/payments/{p['id']}", headers=H(tb)).json()["status"] == "pending"
    state["st"] = "succeeded"
    # уведомление ЮKassa → зачисление (ровно один раз)
    client.post("/coins/yookassa/webhook", json={"event": "payment.succeeded",
                                                 "object": {"id": "yk-1", "metadata": state["meta"]}})
    client.post("/coins/yookassa/webhook", json={"event": "payment.succeeded",
                                                 "object": {"id": "yk-1", "metadata": state["meta"]}})
    r = client.get(f"/coins/payments/{p['id']}", headers=H(tb)).json()
    assert r["status"] == "succeeded" and r["balance"] == before + 1000


def test_gift_upgrade_pin_and_self(client, users, direct):
    ta, tb = tok(users, "a"), tok(users, "b")
    a_id, b_id = uid(users, "a"), uid(users, "b")
    client.post(f"/admin/users/{a_id}/coins", json={"amount": 3000}, headers=H(ta))
    client.post(f"/admin/users/{a_id}/premium", json={"days": 0}, headers=H(ta))
    # себе без Premium — нельзя, с Premium — можно
    r = client.post("/gifts/send", json={"to_user_id": a_id, "gift_id": "rose"}, headers=H(ta))
    assert r.status_code == 403
    client.post(f"/admin/users/{a_id}/premium", json={"days": 30}, headers=H(ta))
    r = client.post("/gifts/send", json={"to_user_id": a_id, "gift_id": "teddy"}, headers=H(ta))
    assert r.status_code == 201, r.text
    mine = r.json()["gift"]
    assert mine["upgrade_cost"] == 25 and mine["unique"] is None
    # улучшение до уникального
    up = client.post(f"/gifts/{mine['id']}/upgrade", headers=H(ta))
    assert up.status_code == 200, up.text
    u = up.json()["gift"]["unique"]
    assert u["no"] == 1 and u["backdrop"]["pct"] > 0 and u["pattern"]["symbol"]
    assert up.json()["gift"]["value"] >= 65 and up.json()["gift"]["convert_value"] == 0
    assert client.post(f"/gifts/{mine['id']}/upgrade", headers=H(ta)).status_code == 400
    assert client.post(f"/gifts/{mine['id']}/convert", headers=H(ta)).status_code == 400
    # закреп наверх
    r2 = client.post("/gifts/send", json={"to_user_id": a_id, "gift_id": "crown"}, headers=H(ta))
    assert r2.status_code == 201
    assert client.put(f"/gifts/{mine['id']}/pin", json={"pinned": True}, headers=H(ta)).json()["pinned"]
    wall = client.get(f"/users/{a_id}/gifts", headers=H(tb)).json()["gifts"]
    assert wall[0]["id"] == mine["id"] and wall[1]["gift"]["id"] == "crown"
    info = client.get("/gifts/upgrade_info", headers=H(tb)).json()
    assert abs(sum(b["pct"] for b in info["backdrops"]) - 100) < 1
    client.post(f"/admin/users/{a_id}/premium", json={"days": 0}, headers=H(ta))


def test_admin_economy_and_gift_and_stories(client, users):
    ta, tc = tok(users, "a"), tok(users, "c")
    c_id = uid(users, "c")
    assert client.get("/admin/economy", headers=H(tc)).status_code == 403
    eco = client.get("/admin/economy", headers=H(ta)).json()
    assert len(eco["gifts"]) == 15 and eco["gifts_total"] >= 3 and eco["top"]
    r = client.post(f"/admin/users/{c_id}/gift", json={"gift_id": "cake"}, headers=H(ta))
    assert r.status_code == 200, r.text
    g = client.get(f"/users/{c_id}/gifts", headers=H(tc)).json()["gifts"]
    assert any(x["gift"]["id"] == "cake" and x["from"] is None for x in g)
    chats = client.get("/chats", headers=H(tc)).json()
    assert any(c["is_system"] and c["last_message"] == "🎁 Подарок" for c in chats)
    hist = client.get(f"/admin/users/{c_id}/coins", headers=H(ta)).json()
    assert isinstance(hist, list)
    st = client.get("/admin/stories", headers=H(ta)).json()
    assert st and "user" in st[0]
    assert client.delete(f"/admin/stories/{st[0]['id']}", headers=H(ta)).status_code == 204


def test_story_overlays_and_ring(client, users):
    ta, tb = tok(users, "a"), tok(users, "b")
    a_id = uid(users, "a")
    client.post(f"/admin/users/{a_id}/premium", json={"days": 30}, headers=H(ta))
    ov = [{"type": "text", "text": "Привет", "style": "neon", "x": 0.5, "y": 0.4},
          {"type": "weather", "temp": 21, "emoji": "☀️", "city": "Нальчик"}]
    r = client.post("/stories", json={"media_url": "/media/p.jpg", "overlays": ov,
                                      "music_url": "/media/song.mp3", "music_title": "Трек"},
                    headers=H(ta))
    assert r.status_code == 201, r.text
    got = client.get(f"/stories/user/{a_id}", headers=H(tb)).json()["stories"][-1]
    assert got["overlays"][0]["style"] == "neon" and got["music_title"] == "Трек"
    # рамка аватара видна другим (премиум-рамка — пока есть Premium)
    client.patch("/me", json={"avatar_ring": "gold"}, headers=H(ta))
    assert client.get(f"/users/{a_id}", headers=H(tb)).json()["avatar_ring"] == "gold"
    client.post(f"/admin/users/{a_id}/premium", json={"days": 0}, headers=H(ta))
    assert client.get(f"/users/{a_id}", headers=H(tb)).json()["avatar_ring"] == "accent"
    assert client.patch("/me", json={"avatar_ring": "weird"}, headers=H(ta)).status_code == 422


# ── удаление аккаунта ──

def test_delete_account(client, users, direct):
    tb = tok(users, "b")
    client.post("/bots", json={"name": "Мой", "username": "bobs_bot"}, headers=H(tb))
    assert client.delete("/me", headers=H(tb)).status_code == 204
    assert client.get("/me", headers=H(tb)).status_code == 401
    chats = client.get("/chats", headers=H(tok(users, "a"))).json()
    d = next(c for c in chats if c["id"] == direct)
    assert d["title"] == "Удалённый аккаунт"
    assert client.get("/users/search?q=bobs", headers=H(tok(users, "a"))).json() == []


def test_support_in_admin_dms(client, users):
    ta, tb = tok(users, "a"), tok(users, "c")
    sysb = next(c for c in client.get("/chats", headers=H(tb)).json() if c["is_system"])
    r = client.post(f"/chats/{sysb['id']}/messages", json={"text": "Помогите с оплатой"},
                    headers=H(tb))
    assert r.status_code == 201
    # у админа — отдельный чат с Бобом, помеченный как поддержка
    alist = client.get("/chats", headers=H(ta)).json()
    sup = next(c for c in alist if c["id"] == sysb["id"])
    assert sup["support"] is True and sup["is_system"] is False
    assert sup["peer_id"] == uid(users, "c") and sup["title"] == "Carl"
    assert sup["unread_count"] >= 1 and sup["last_message"] == "Помогите с оплатой"
    # свой чат «Connecto» у админа никуда не делся
    own = [c for c in alist if c["is_system"]]
    assert len(own) == 1 and own[0]["id"] != sysb["id"]
    bot_id = sup["support_bot_id"]
    # админ отвечает — человек видит ответ от Connecto
    r = client.post(f"/chats/{sysb['id']}/messages", json={"text": "Уже смотрю!"}, headers=H(ta))
    assert r.status_code == 201 and r.json()["sender_id"] == bot_id
    msgs = client.get(f"/chats/{sysb['id']}/messages", headers=H(tb)).json()
    assert msgs[-1]["text"] == "Уже смотрю!" and msgs[-1]["sender_id"] == bot_id
    # человек не видит админов в участниках и собеседник у него — Connecto
    binfo = client.get(f"/chats/{sysb['id']}", headers=H(tb)).json()
    assert binfo["peer_id"] == bot_id and uid(users, "a") not in binfo["members"]
    # у админа свой ответ — «свой», непрочитанных нет после ответа и чтения
    client.post(f"/chats/{sysb['id']}/read", headers=H(ta))
    sup = next(c for c in client.get("/chats", headers=H(ta)).json() if c["id"] == sysb["id"])
    assert sup["last_mine"] is True and sup["unread_count"] == 0
    # служебные уведомления Connecto (приветствие, входы) админу не показываются
    amsgs = client.get(f"/chats/{sysb['id']}/messages", headers=H(ta)).json()
    assert all(m["sender_id"] != bot_id or (m.get("extra") or {}).get("support") for m in amsgs)
    assert any(m["sender_id"] == bot_id for m in msgs[:-1])   # а у человека они есть
    # реакция админа — от имени Connecto
    r = client.post(f"/chats/{sysb['id']}/messages/{amsgs[0]['id']}/react", json={"emoji": "👍"},
                    headers=H(ta)).json()
    assert r["reactions"][0]["mine"] is True
    cm = client.get(f"/chats/{sysb['id']}/messages", headers=H(tb)).json()
    rr = next(m for m in cm if m["id"] == amsgs[0]["id"])["reactions"][0]
    assert uid(users, "a") not in rr.get("user_ids", []) and bot_id in rr.get("user_ids", [bot_id])
    # автоудаление в чате Connecto недоступно
    assert client.put(f"/chats/{sysb['id']}/ttl", json={"seconds": 60}, headers=H(ta)).status_code == 403
    # админ может поправить свой ответ
    mid = msgs[-1]["id"]
    assert client.patch(f"/chats/{sysb['id']}/messages/{mid}", json={"text": "Уже смотрю 👀"},
                        headers=H(ta)).status_code == 200
    # личка админа с Бобом — отдельный обычный чат
    d = client.post("/chats", json={"type": "direct", "member_ids": [uid(users, "c")]},
                    headers=H(ta)).json()
    assert d["id"] != sysb["id"] and d.get("support") is False
    # админ убирает обращение у себя — у человека чат остаётся
    assert client.delete(f"/chats/{sysb['id']}?scope=both", headers=H(ta)).status_code == 204
    assert all(c["id"] != sysb["id"] for c in client.get("/chats", headers=H(ta)).json())
    assert any(c["id"] == sysb["id"] for c in client.get("/chats", headers=H(tb)).json())
    # человек пишет снова — обращение возвращается
    client.post(f"/chats/{sysb['id']}/messages", json={"text": "Ещё вопрос"}, headers=H(tb))
    assert any(c["id"] == sysb["id"] and c["support"]
               for c in client.get("/chats", headers=H(ta)).json())


def test_shop_seller_and_rollypay(client, users, monkeypatch):
    ta, tb = tok(users, "a"), tok(users, "c")
    shop = client.get("/coins/shop", headers=H(tb)).json()
    assert shop["seller"]["user_id"] == uid(users, "a") and shop["seller"]["telegram"] == "kemq78"
    assert all("rub" in p for p in shop["premium_plans"])
    assert client.get("/coins", headers=H(tb)).json()["seller"]["user_id"] == uid(users, "a")
    # RollyPay: подпись вебхука и зачисление (модуль пока не подключён к приложению)
    import hashlib
    import hmac
    import time
    from app.routers import rollypay
    from app.database import SessionLocal
    from app.models.social import Payment
    from app.models.user import User
    ts = str(int(time.time()))
    body = b'{"event":"payment.paid"}'
    sig = hmac.new(b"sec", ts.encode() + b"." + body, hashlib.sha256).hexdigest()
    assert rollypay._check_signature("sec", ts, body, sig)
    assert rollypay._check_signature("sec", ts, body, "sha256=" + sig)
    assert not rollypay._check_signature("sec", ts, body + b"x", sig)
    assert not rollypay._check_signature("sec", "1", body, sig)
    monkeypatch.setattr(rollypay, "rp_cfg", lambda: {"api_key": "k", "signing_secret": "sec"})
    db = SessionLocal()
    try:
        me = db.query(User).filter(User.id == uid(users, "c")).first()
        monkeypatch.setattr(rollypay, "_rp", lambda m, p, b=None: {"payment_id": "X1",
                                                                  "pay_url": "https://pay"})
        out = rollypay.create_coins_payment(db, me, {"id": "c100", "coins": 100, "rub": 49})
        assert out["confirmation_url"] == "https://pay"
        pay = db.query(Payment).filter(Payment.id == out["id"]).first()
        before = int(me.coins or 0)
        monkeypatch.setattr(rollypay, "_rp", lambda m, p, b=None: {"status": "PAID",
                                                                  "order_id": pay.id})
        rollypay.sync_payment(db, pay)
        rollypay.sync_payment(db, pay)   # второй раз не начисляет
        db.refresh(me)
        assert pay.status == "succeeded" and int(me.coins) == before + 100
    finally:
        db.close()


def test_e2e_keys_and_envelopes(client, users):
    import base64
    import json as _j
    ta, tc = tok(users, "a"), tok(users, "c")
    k1 = base64.b64encode(b"\x01" * 32).decode()
    k2 = base64.b64encode(b"\x02" * 32).decode()
    assert client.put("/keys", json={"device_id": "devA", "public_key": "bad"},
                      headers=H(ta)).status_code == 422
    ra = client.put("/keys", json={"device_id": "devA", "public_key": k1}, headers=H(ta)).json()
    rc = client.put("/keys", json={"device_id": "devC", "public_key": k2}, headers=H(tc)).json()
    # тот же ключ повторно — тот же key_id
    assert client.put("/keys", json={"device_id": "devA", "public_key": k1},
                      headers=H(ta)).json()["key_id"] == ra["key_id"]
    d = client.post("/chats", json={"type": "direct", "member_ids": [uid(users, "c")]},
                    headers=H(ta)).json()
    keys = client.get(f"/chats/{d['id']}/keys", headers=H(ta)).json()
    assert keys["enabled"] is True
    assert {k["key_id"] for k in keys["keys"]} == {ra["key_id"], rc["key_id"]}
    env = _j.dumps({"v": 1, "sp": k1, "c": "Y2lwaGVy", "k": {ra["key_id"]: "eA==", rc["key_id"]: "eQ=="}})
    r = client.post(f"/chats/{d['id']}/messages", json={"text": "секрет", "enc": env}, headers=H(ta))
    assert r.status_code == 201 and r.json()["text"] == "" and r.json()["enc"] == env
    msgs = client.get(f"/chats/{d['id']}/messages", headers=H(tc)).json()
    assert msgs[-1]["enc"] == env and msgs[-1]["text"] == ""
    lst = next(c for c in client.get("/chats", headers=H(tc)).json() if c["id"] == d["id"])
    assert lst["last_message"] == "🔒 Сообщение" and lst["last_enc"] == env
    # правка зашифрованного
    env2 = env.replace("Y2lwaGVy", "bmV3")
    e = client.patch(f"/chats/{d['id']}/messages/{r.json()['id']}", json={"enc": env2}, headers=H(ta))
    assert e.status_code == 200 and e.json()["enc"] == env2
    # мусор вместо конверта — отказ
    assert client.post(f"/chats/{d['id']}/messages", json={"enc": "{}"},
                       headers=H(ta)).status_code == 400
    # в чате Connecto шифрования нет
    sysc = next(c for c in client.get("/chats", headers=H(tc)).json() if c["is_system"])
    assert client.get(f"/chats/{sysc['id']}/keys", headers=H(tc)).json()["enabled"] is False
    assert client.post(f"/chats/{sysc['id']}/messages", json={"enc": env},
                       headers=H(tc)).status_code == 400


# ── звонки ──

def _recv(ws, typ, limit=12):
    for _ in range(limit):
        ev = ws.receive_json()
        if ev.get("type") == typ:
            return ev
    raise AssertionError(f"не дождались {typ}")


def test_calls_signaling(client, users, monkeypatch):
    from app import calls
    d = register(client, "dima", "dima@x.ru", "devD")
    e = register(client, "egor", "egor@x.ru", "devE")
    td, te = d["access_token"], e["access_token"]
    cid = client.post("/chats", json={"type": "direct", "member_ids": [e["user"]["id"]]},
                      headers=H(td)).json()["id"]
    p = client.get(f"/calls/prepare?chat_id={cid}", headers=H(td))
    assert p.status_code == 200, p.text
    assert p.json()["relay"] is False and p.json()["peer"]["name"] == "Egor"
    assert any("stun:" in u for s in p.json()["ice_servers"] for u in s["urls"])
    # свой TURN: временный логин и пароль
    monkeypatch.setattr(calls.settings, "turn_secret", "s3cret")
    turn = [s for s in client.get(f"/calls/prepare?chat_id={cid}", headers=H(td)).json()["ice_servers"]
            if "username" in s]
    assert turn and turn[0]["credential"] and turn[0]["username"].endswith(d["user"]["id"])
    monkeypatch.setattr(calls.settings, "turn_secret", "")
    # звонить можно только в личке
    sysc = next(c for c in client.get("/chats", headers=H(td)).json() if c["is_system"])
    assert client.get(f"/calls/prepare?chat_id={sysc['id']}", headers=H(td)).status_code == 403

    call = "call_0001abcd"
    with client.websocket_connect(f"/ws?token={te}") as we, \
            client.websocket_connect(f"/ws?token={td}") as wd:
        wd.send_json({"type": "call.invite", "call_id": call, "chat_id": cid, "video": True,
                      "sdp": "v=0 offer"})
        inc = _recv(we, "call.incoming")
        assert inc["video"] is True and inc["sdp"] == "v=0 offer" and inc["from"]["name"] == "Dima"
        assert _recv(wd, "call.sent")["online"] is True
        wd.send_json({"type": "call.ice", "call_id": call,
                      "candidate": {"candidate": "c1", "sdpMid": "0", "sdpMLineIndex": 0}})
        assert _recv(we, "call.ice")["candidate"]["candidate"] == "c1"
        we.send_json({"type": "call.ringing", "call_id": call})
        _recv(wd, "call.ringing")
        we.send_json({"type": "call.accept", "call_id": call, "sdp": "v=0 answer"})
        assert _recv(wd, "call.accepted")["sdp"] == "v=0 answer"
        _recv(we, "call.taken")
        we.send_json({"type": "call.sdp", "call_id": call, "sdp": "v=0 restart", "sdp_type": "offer"})
        assert _recv(wd, "call.sdp")["sdp_type"] == "offer"
        wd.send_json({"type": "call.end", "call_id": call})
        assert _recv(we, "call.ended")["reason"] == "ended"
        assert _recv(wd, "call.ended")["reason"] == "ended"
        m = _recv(we, "message")
        assert m["kind"] == "call" and m["extra"]["call"]["status"] == "ended"
        assert m["extra"]["call"]["video"] is True
        assert call not in calls.CALLS and not calls.BY_USER

        # не дозвонились — «пропущенный»
        monkeypatch.setattr(calls, "RING_TIMEOUT", 0.3)
        wd.send_json({"type": "call.invite", "call_id": "call_0002abcd", "chat_id": cid,
                      "video": False, "sdp": "v=0"})
        _recv(we, "call.incoming")
        assert _recv(wd, "call.ended")["reason"] == "missed"
        monkeypatch.setattr(calls, "RING_TIMEOUT", 45)

        # отклонили
        wd.send_json({"type": "call.invite", "call_id": "call_0003abcd", "chat_id": cid,
                      "video": False, "sdp": "v=0"})
        _recv(we, "call.incoming")
        we.send_json({"type": "call.decline", "call_id": "call_0003abcd"})
        assert _recv(wd, "call.ended")["reason"] == "declined"

    lst = {c["id"]: c for c in client.get("/chats", headers=H(te)).json()}
    assert lst[cid]["last_message"] == "📞 Отклонённый звонок"
    msgs = client.get(f"/chats/{cid}/messages", headers=H(te)).json()
    statuses = [x["extra"]["call"]["status"] for x in msgs if x["kind"] == "call"]
    assert statuses == ["ended", "missed", "declined"]
    from app.messaging import preview_text
    from app.database import SessionLocal
    from app.models.chat import Message
    db = SessionLocal()
    try:
        missed = [x for x in db.query(Message).filter(Message.chat_id == cid, Message.kind == "call")
                  if '"missed"' in x.extra][0]
        assert preview_text(missed, e["user"]["id"]) == "📞 Пропущенный звонок"
        assert preview_text(missed, d["user"]["id"]) == "📞 Отменённый звонок"
    finally:
        db.close()

    # собеседник был не в сети — звонок приходит, когда он откроет приложение
    with client.websocket_connect(f"/ws?token={td}") as wd:
        wd.send_json({"type": "call.invite", "call_id": "call_0004abcd", "chat_id": cid,
                      "video": False, "sdp": "v=0"})
        assert _recv(wd, "call.sent")["online"] is False
        wd.send_json({"type": "call.ice", "call_id": "call_0004abcd",
                      "candidate": {"candidate": "early", "sdpMid": "0", "sdpMLineIndex": 0}})
        with client.websocket_connect(f"/ws?token={te}") as we:
            inc = _recv(we, "call.incoming")
            assert inc["call_id"] == "call_0004abcd" and inc["ice"][0]["candidate"] == "early"
            we.send_json({"type": "call.end", "call_id": "call_0004abcd"})
            assert _recv(wd, "call.ended")["reason"] == "declined"

    # приватность: «кто может звонить — никто»
    client.put("/me/privacy", json={"values": {"calls": "none"}}, headers=H(te))
    assert client.get(f"/calls/prepare?chat_id={cid}", headers=H(td)).status_code == 403
    with client.websocket_connect(f"/ws?token={td}") as wd:
        wd.send_json({"type": "call.invite", "call_id": "call_0005abcd", "chat_id": cid,
                      "video": False, "sdp": "v=0"})
        err = _recv(wd, "call.error")
        assert err["reason"] == "privacy"
    client.put("/me/privacy", json={"values": {"calls": "all", "p2p": "none"}}, headers=H(te))
    # «peer-to-peer: никто» работает только при настроенном TURN
    assert client.get(f"/calls/prepare?chat_id={cid}", headers=H(te)).json()["relay"] is False
    monkeypatch.setattr(calls.settings, "turn_secret", "s3cret")
    assert client.get(f"/calls/prepare?chat_id={cid}", headers=H(te)).json()["relay"] is True
    assert client.get(f"/calls/prepare?chat_id={cid}", headers=H(td)).json()["relay"] is False


def test_round_video_message(client, users):
    ta, tc = tok(users, "a"), tok(users, "c")
    d = client.post("/chats", json={"type": "direct", "member_ids": [uid(users, "c")]},
                    headers=H(ta)).json()
    r = client.post(f"/chats/{d['id']}/messages",
                    json={"kind": "round", "media_url": "/media/r.mp4", "text": "round:4200"},
                    headers=H(ta))
    assert r.status_code == 201 and r.json()["kind"] == "round"
    lst = next(c for c in client.get("/chats", headers=H(tc)).json() if c["id"] == d["id"])
    assert lst["last_message"] == "📹 Видеосообщение"
    # запрет голосовых распространяется и на видеосообщения
    client.put("/me/privacy", json={"values": {"voice": "none"}}, headers=H(tc))
    r = client.post(f"/chats/{d['id']}/messages",
                    json={"kind": "round", "media_url": "/media/r.mp4"}, headers=H(ta))
    assert r.status_code == 403
    client.put("/me/privacy", json={"values": {"voice": "all"}}, headers=H(tc))


def test_calls_devices_sync_restart(client, users):
    from app import calls
    f = register(client, "fedya", "fedya@x.ru", "devF")
    g = register(client, "gleb", "gleb@x.ru", "devG")
    tf, tg = f["access_token"], g["access_token"]
    cid = client.post("/chats", json={"type": "direct", "member_ids": [g["user"]["id"]]},
                      headers=H(tf)).json()["id"]
    call = "call_devs_0001"
    with client.websocket_connect(f"/ws?token={tg}") as g1, \
            client.websocket_connect(f"/ws?token={tg}") as g2, \
            client.websocket_connect(f"/ws?token={tf}") as wf:
        wf.send_json({"type": "call.invite", "call_id": call, "chat_id": cid, "video": False,
                      "sdp": "v=0", "device": "F1"})
        _recv(g1, "call.incoming")
        _recv(g2, "call.incoming")
        g1.send_json({"type": "call.accept", "call_id": call, "sdp": "ans", "device": "G1"})
        assert _recv(wf, "call.accepted")["sdp"] == "ans"
        assert _recv(g2, "call.taken")["device"] == "G1"
        # второй телефон тоже нажал «ответить» — ему снова говорят, что ответили на G1
        g2.send_json({"type": "call.accept", "call_id": call, "sdp": "ans2", "device": "G2"})
        assert _recv(g2, "call.taken")["device"] == "G1"
        # «завершить» со второго телефона не рвёт чужой разговор
        g2.send_json({"type": "call.end", "call_id": call, "device": "G2"})
        assert call in calls.CALLS
        # собеседник сменил сеть — звонящему приходит просьба перезапустить соединение
        g1.send_json({"type": "call.restart", "call_id": call, "device": "G1"})
        _recv(wf, "call.restart")
        # звонящий переподключился и потерял call.accepted — сервер повторит
        wf.send_json({"type": "call.sync", "call_id": call, "device": "F1"})
        assert _recv(wf, "call.accepted")["sdp"] == "ans"
        # приложение звонящего перезапустилось: звонка у клиента нет — сервер закрывает
        wf.send_json({"type": "call.sync", "call_id": None, "device": "F1"})
        assert _recv(g1, "call.ended")["reason"] == "ended"
        assert _recv(wf, "call.ended")["call_id"] == call
        assert call not in calls.CALLS and not calls.BY_USER
        # клиент думает, что звонок идёт, а сервер его уже забыл
        wf.send_json({"type": "call.sync", "call_id": "call_ghost_01", "device": "F1"})
        assert _recv(wf, "call.ended")["call_id"] == "call_ghost_01"


def test_qr_login(client, users):
    from app.routers import auth as auth_router
    h = register(client, "hana", "hana@x.ru", "devH")
    th = h["access_token"]
    st = client.post("/auth/qr/start", json={"device_id": "pc-1", "platform": "Windows"}).json()
    assert st["qr"].startswith("connecto-login:") and len(st["code"]) == 8
    assert client.get(f"/auth/qr/{st['token']}").json()["status"] == "pending"
    # без входа подтвердить нельзя
    assert client.post("/auth/qr/approve", json={"token": st["token"]}).status_code == 401
    info = client.post("/auth/qr/inspect", json={"code": st["code"].lower()}, headers=H(th))
    assert info.status_code == 200 and info.json()["platform"] == "Windows"
    assert client.get(f"/auth/qr/{st['token']}").json()["status"] == "scanned"
    ok = client.post("/auth/qr/approve", json={"token": st["token"]}, headers=H(th))
    assert ok.status_code == 200
    r = client.get(f"/auth/qr/{st['token']}").json()
    assert r["status"] == "approved" and r["user"]["username"] == "hana"
    me = client.get("/me", headers=H(r["access_token"]))
    assert me.status_code == 200
    sessions = client.get("/sessions", headers=H(th)).json()
    assert any(s["platform"] == "Windows" for s in sessions)
    # токены выдаются один раз
    assert client.get(f"/auth/qr/{st['token']}").json()["status"] == "expired"
    # чужой/неверный код
    assert client.post("/auth/qr/approve", json={"code": "ZZZZZZZZ"}, headers=H(th)).status_code == 404
    # с облачным паролем компьютер получает «нужен пароль»
    st2 = client.post("/auth/qr/start", json={"device_id": "pc-2", "platform": "Windows"}).json()
    from app.database import SessionLocal
    from app.models.user import User
    from app.core.security import hash_password
    db = SessionLocal()
    try:
        u = db.query(User).filter(User.username == "hana").first()
        u.cloud_password_hash = hash_password("secret42")
        db.commit()
    finally:
        db.close()
    client.post("/auth/qr/approve", json={"token": st2["token"]}, headers=H(th))
    r2 = client.get(f"/auth/qr/{st2['token']}").json()
    assert r2["status"] == "approved" and r2["needs_password"] is True
    fin = client.post("/auth/login/2fa", json={"ticket": r2["ticket"], "password": "secret42"})
    assert fin.status_code == 200 and "access_token" in fin.json()
    assert auth_router.QR_TTL == 120


# ── внешние API и встроенные боты ──

def _wait_bot_reply(client, t, chat_id, n_before, timeout=6.0):
    import time as _t
    end = _t.time() + timeout
    while _t.time() < end:
        msgs = client.get(f"/chats/{chat_id}/messages", headers=H(t)).json()
        if len(msgs) > n_before and msgs[-1]["sender_is_bot"]:
            return msgs[-1]
        _t.sleep(0.1)
    raise AssertionError("бот не ответил")


def test_ext_apis_and_builtin_bots(client, users, monkeypatch):
    from app import extapi
    tb = register(client, "gina", "gina@x.ru", "devG")["access_token"]

    async def fake_translate(text, to="ru", src="auto"):
        return {"text": f"[{to}] {text}", "from": "en" if to == "ru" else "ru", "to": to,
                "provider": "test"}

    async def fake_json(url, params=None, headers=None):
        if "nekos.best" in url:
            return {"results": [{"url": "https://nekos.best/api/v2/hug/1.gif", "anime_name": "A"}]}
        if "itunes.apple.com" in url:
            return {"results": [{"trackId": 1, "trackName": "Song", "artistName": "Artist",
                                 "artworkUrl100": "https://is1.mzstatic.com/x/100x100bb.jpg",
                                 "previewUrl": "https://audio-ssl.itunes.apple.com/p.m4a",
                                 "trackTimeMillis": 200000}]}
        if "cbr-xml-daily" in url:
            return {"Date": "2026-09-27T11:30:00+03:00", "Valute": {
                "USD": {"Nominal": 1, "Value": 90.0, "Previous": 89.0, "Name": "Доллар США"},
                "EUR": {"Nominal": 1, "Value": 100.0, "Previous": 101.0, "Name": "Евро"}}}
        if "coingecko" in url:
            return {"bitcoin": {"usd": 60000, "rub": 5400000, "usd_24h_change": 1.5}}
        if "geocoding-api" in url:
            return {"results": [{"name": "Москва", "latitude": 55.75, "longitude": 37.62,
                                 "country": "Россия"}]}
        if "api.open-meteo.com" in url:
            return {"current": {"temperature_2m": 12.3, "apparent_temperature": 10,
                                "relative_humidity_2m": 70, "weather_code": 2, "wind_speed_10m": 3},
                    "daily": {"time": ["2026-09-27", "2026-09-28", "2026-09-29"],
                              "weather_code": [3, 61, 0], "temperature_2m_min": [8, 7, 5],
                              "temperature_2m_max": [14, 11, 13],
                              "precipitation_probability_max": [20, 80, 0]}}
        if "uselessfacts" in url:
            return {"text": "Honey never spoils."}
        raise RuntimeError("unexpected " + url)

    async def fake_download(url, max_bytes=0, kinds=()):
        if not extapi.host_allowed(url):
            raise extapi.ExtError("Эту ссылку загрузить нельзя")
        return {"url": "/media/fake.gif", "size": 10, "type": "image/gif"}

    monkeypatch.setattr(extapi, "translate", fake_translate)
    monkeypatch.setattr(extapi, "get_json", fake_json)
    monkeypatch.setattr(extapi, "download", fake_download)
    extapi._cache.clear()

    # GIF без ключа — реакции nekos.best
    g = client.get("/ext/gifs?q=Обнять", headers=H(tb)).json()
    assert "provider" in g, g
    assert g["provider"] == "nekos" and g["items"][0]["url"].endswith(".gif") and g["categories"]
    r = client.post("/ext/gifs/import", json={"url": "https://nekos.best/api/v2/hug/1.gif"},
                    headers=H(tb))
    assert r.status_code == 200 and r.json()["url"] == "/media/fake.gif"
    bad = client.post("/ext/gifs/import", json={"url": "http://127.0.0.1:8000/secret"},
                      headers=H(tb))
    assert bad.status_code == 503
    # перевод
    r = client.post("/ext/translate", json={"text": "hello", "to": "ru"}, headers=H(tb))
    assert r.json()["text"] == "[ru] hello"
    assert any(x["code"] == "de" for x in client.get("/ext/translate/langs").json())
    # музыка
    mu = client.get("/ext/music?q=song", headers=H(tb)).json()
    assert mu[0]["title"] == "Song" and "600x600bb" in mu[0]["cover"]
    assert client.post("/ext/music/import", json={"url": mu[0]["preview"]},
                       headers=H(tb)).status_code == 200
    assert extapi.guess_lang("Привет, как дела") == "ru" and extapi.guess_lang("hi there") == "en"

    # встроенные боты
    bots = client.get("/ext/bots", headers=H(tb)).json()
    assert {b["key"] for b in bots} == {"weather", "rates", "fun", "translate"}
    by = {b["key"]: b for b in bots}

    def talk(key, text):
        chat = client.post("/chats", json={"type": "direct", "member_ids": [by[key]["id"]]},
                           headers=H(tb)).json()
        n = len(client.get(f"/chats/{chat['id']}/messages", headers=H(tb)).json())
        client.post(f"/chats/{chat['id']}/messages", json={"text": text}, headers=H(tb))
        return _wait_bot_reply(client, tb, chat["id"], n + 1)

    assert "Москва" in talk("weather", "Москва")["text"]
    assert "+12°" in talk("weather", "погода в Москве")["text"]
    rr = talk("rates", "100 usd")
    assert "9 000" in rr["text"] and "RUB" in rr["text"]
    assert "USD" in talk("rates", "/rates")["text"]
    assert "BTC" in talk("rates", "1 btc")["text"]
    assert talk("translate", "hello")["text"].startswith("[ru] hello")
    assert talk("translate", "привет")["text"].startswith("[en] привет")
    assert "немецкий" in talk("translate", "/to de")["text"]
    assert talk("translate", "привет")["text"].startswith("[de]")
    assert "Honey" in talk("fun", "/fact")["text"]


def test_admin_gift_shop_and_sale_window(client, users):
    """Подарки из админки: новый, сезонный (окно продажи), тираж, снятие с продажи."""
    from datetime import datetime, timedelta, timezone
    ta, tc = tok(users, "a"), tok(users, "c")
    now = datetime.now(timezone.utc)
    # обычный пользователь в админку не пускается
    assert client.get("/admin/gifts", headers=H(tc)).status_code == 403
    # встроенные подарки перенесены в базу
    ids = [g["id"] for g in client.get("/admin/gifts", headers=H(ta)).json()]
    assert "rose" in ids and "dragon" in ids
    # хэллоуинский: продаётся сейчас, тираж 2
    r = client.post("/admin/gifts", json={
        "id": "pumpkin", "title": "Тыква", "emoji": "🎃", "price": 10, "rarity": "epic",
        "supply": 2, "colors": ["#FF8A00", "#7C2D12", "bad"],
        "sale_from": (now - timedelta(hours=1)).isoformat(),
        "sale_until": (now + timedelta(days=3)).isoformat()}, headers=H(ta))
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "on_sale" and r.json()["colors"] == ["#FF8A00", "#7C2D12"]
    # будущий — в магазине не виден
    assert client.post("/admin/gifts", json={
        "id": "ny_tree", "title": "Ёлка", "emoji": "🎄", "price": 10, "rarity": "rare",
        "sale_from": (now + timedelta(days=30)).isoformat()}, headers=H(ta)).json()["status"] == "soon"
    assert client.post("/admin/gifts", json={"title": "x", "price": 1, "rarity": "mythic"},
                       headers=H(ta)).status_code == 400
    cat = [g["id"] for g in client.get("/gifts/catalog", headers=H(tc)).json()["gifts"]]
    assert "pumpkin" in cat and "ny_tree" not in cat
    client.post(f"/admin/users/{uid(users, 'c')}/coins", json={"amount": 100}, headers=H(ta))
    send = lambda gid: client.post("/gifts/send", json={"to_user_id": uid(users, "a"),
                                                        "gift_id": gid}, headers=H(tc))
    assert send("ny_tree").status_code == 410
    assert send("pumpkin").status_code == 201
    assert send("pumpkin").json()["gift"]["serial"] == 2
    assert send("pumpkin").status_code == 410       # тираж кончился
    # тираж меньше проданного — нельзя
    g = client.get("/admin/gifts", headers=H(ta)).json()
    pk = next(x for x in g if x["id"] == "pumpkin")
    assert pk["sold"] == 2 and pk["left"] == 0
    body = {k: pk[k] for k in ("title", "emoji", "price", "rarity")} | {"supply": 1}
    assert client.put("/admin/gifts/pumpkin", json=body, headers=H(ta)).status_code == 400
    # купленный подарок не удаляется, а снимается с продажи; у владельца он остаётся
    assert client.delete("/admin/gifts/pumpkin", headers=H(ta)).json()["hidden"] is True
    mine = client.get(f"/users/{uid(users, 'a')}/gifts", headers=H(ta)).json()["gifts"]
    assert any(x["gift"]["id"] == "pumpkin" and x["gift"]["emoji"] == "🎃" for x in mine)
    assert client.delete("/admin/gifts/ny_tree", headers=H(ta)).json()["deleted"] is True


def test_admin_release_upload(client, users):
    ta, tc = tok(users, "a"), tok(users, "c")
    apk = b"PK\x03\x04" + b"0" * (1024 * 1024 + 10)
    files = {"file": ("app.apk", apk, "application/vnd.android.package-archive")}
    form = {"platform": "android", "version": "1.0.1", "build": "8", "notes": "Новое:\n- папки"}
    assert client.post("/admin/release", data=form, files=files, headers=H(tc)).status_code == 403
    assert client.post("/admin/release", data=form | {"platform": "android"},
                       files={"file": ("x.apk", b"MZ" + b"0" * 2_000_000, "x")},
                       headers=H(ta)).status_code == 400          # не APK
    r = client.post("/admin/release", data=form, files=files, headers=H(ta))
    assert r.status_code == 200, r.text
    v = client.get("/app_version").json()
    assert v["build"] == 8 and v["version"] == "1.0.1" and "папки" in v["notes"]
    assert v["url_direct"].endswith("/download/Connecto.apk?b=8")
    # та же сборка второй раз — нельзя; без файла — правим только текст
    assert client.post("/admin/release", data=form, files=files, headers=H(ta)).status_code == 400
    r = client.post("/admin/release", data=form | {"notes": "Исправлено", "mandatory": "true"},
                    headers=H(ta))
    assert r.json()["android"]["notes"] == "Исправлено" and r.json()["android"]["mandatory"]
    assert client.get("/app_version").json()["build"] == 8
    assert client.get("/download/Connecto.apk").content == apk


def test_admin_gift_image_and_style(client, users):
    """Картинка на белом фоне → прозрачный PNG; оформление подарка сохраняется."""
    import io
    from PIL import Image, ImageDraw
    ta = tok(users, "a")
    im = Image.new("RGB", (600, 400), (255, 255, 255))
    d = ImageDraw.Draw(im)
    d.ellipse((200, 100, 400, 300), fill=(255, 120, 0))
    d.ellipse((280, 180, 320, 220), fill=(255, 255, 255))   # белое пятно внутри — остаётся
    b = io.BytesIO()
    im.save(b, "JPEG")
    r = client.post("/admin/gifts/image", files={"file": ("p.jpg", b.getvalue(), "image/jpeg")},
                    headers=H(ta))
    assert r.status_code == 200, r.text
    assert r.json()["removed_bg"] is True
    png = client.get(r.json()["url"]).content
    out = Image.open(io.BytesIO(png))
    assert out.size == (512, 512) and out.mode == "RGBA"
    assert out.getpixel((2, 2))[3] == 0                    # угол прозрачный
    assert out.getpixel((256, 256))[3] == 255              # белая серединка предмета осталась
    # переделать уже загруженную
    assert client.post("/admin/gifts/image", data={"src": r.json()["url"]},
                       headers=H(ta)).status_code == 200
    # оформление
    g = client.post("/admin/gifts", json={"title": "Звезда", "price": 5, "rarity": "rare",
                                          "bg": "starry", "fx": "float", "anim": "swing",
                                          "symbol": "🦇", "image_url": r.json()["url"]},
                    headers=H(ta)).json()
    assert g["bg"] == "starry" and g["fx"] == "float" and g["symbol"] == "🦇"
    assert client.post("/admin/gifts", json={"title": "x", "price": 5, "bg": "lava"},
                       headers=H(ta)).status_code == 400
    cat = client.get("/gifts/catalog", headers=H(ta)).json()["gifts"]
    assert any(x["id"] == g["id"] and x["anim"] == "swing" for x in cat)


# ── магазин оформления ──

def test_shop_admin_catalog_buy_equip(client, users):
    """Товары из админки, витрина, поиск, фильтры, покупка, надевание, подарок другу."""
    from datetime import datetime, timedelta, timezone
    ta = tok(users, "a")
    sb = register(client, "shopper", "shopper@x.ru", "devS1")
    sc = register(client, "shopgal", "shopgal@x.ru", "devS2")
    tb, tc = sb["access_token"], sc["access_token"]
    ids = {"a": uid(users, "a"), "b": sb["user"]["id"], "c": sc["user"]["id"]}
    now = datetime.now(timezone.utc)
    assert client.get("/admin/shop/items", headers=H(tb)).status_code == 403
    r = client.post("/admin/shop/collections", json={
        "id": "halloween", "title": "Хэллоуин", "subtitle": "Только до 1 ноября",
        "colors": ["#FF7A00", "#1A0B2E"], "sale_until": (now + timedelta(days=20)).isoformat()},
        headers=H(ta))
    assert r.status_code == 201, r.text
    mk = lambda body: client.post("/admin/shop/items", json=body, headers=H(ta))
    assert mk({"id": "cv_moon", "kind": "cover", "title": "Кровавая Луна", "price": 100,
               "discount": 20, "rarity": "epic", "collection": "halloween", "tags": "ночь тыквы",
               "media_url": "/media/shop/x.mp4", "media_kind": "video"}).status_code == 201
    assert mk({"id": "fr_fire", "kind": "frame", "title": "Огненное кольцо", "price": 50,
               "supply": 1, "media_url": "/media/shop/f.webp"}).status_code == 201
    assert mk({"id": "fx_snow", "kind": "effect", "title": "Снегопад", "price": 0,
               "media_url": "/media/shop/s.webp"}).status_code == 201
    assert mk({"id": "wp_city", "kind": "wallpaper", "title": "Ночной город", "price": 40,
               "premium_free": True, "media_url": "/media/shop/w.jpg"}).status_code == 201
    assert mk({"id": "cv_soon", "kind": "cover", "title": "Ёлки", "price": 10,
               "sale_from": (now + timedelta(days=40)).isoformat()}).status_code == 201
    # валидация
    assert mk({"kind": "hat", "title": "x"}).status_code == 400
    assert mk({"kind": "frame", "title": "x", "media_kind": "video"}).status_code == 400
    assert mk({"id": "cv_moon", "kind": "cover", "title": "дубль"}).status_code == 409
    # витрина
    home = client.get("/shop", headers=H(tb)).json()
    assert home["total"] == 4                                  # будущий не виден
    assert home["banners"][0]["id"] == "halloween" and home["banners"][0]["count"] == 1
    assert [x["id"] for x in home["sale"]] == ["cv_moon"]
    assert home["sale"][0]["final_price"] == 80 and home["sale"][0]["discount"] == 20
    assert [x["id"] for x in home["free"]] == ["fx_snow"]
    assert {k["id"]: k["count"] for k in home["kinds"]}["cover"] == 1
    # поиск без учёта регистра (кириллица), по тегам и коллекции
    srch = lambda **p: client.get("/shop/items", params=p, headers=H(tb)).json()
    assert [x["id"] for x in srch(q="луна")["items"]] == ["cv_moon"]
    assert [x["id"] for x in srch(q="ТЫКВЫ")["items"]] == ["cv_moon"]
    assert [x["id"] for x in srch(q="хэллоуин")["items"]] == ["cv_moon"]
    assert srch(kind="frame")["total"] == 1
    assert [x["id"] for x in srch(filter="limited")["items"]] == ["fr_fire"]
    assert [x["id"] for x in srch(sort="price_desc")["items"]][0] == "cv_moon"
    assert srch(collection="halloween")["collection"]["title"] == "Хэллоуин"
    # покупка: не хватает коинов
    buy = lambda t, iid, **b: client.post(f"/shop/items/{iid}/buy", json=b, headers=H(t))
    assert buy(tb, "cv_moon").status_code == 402
    client.post(f"/admin/users/{ids['b']}/coins", json={"amount": 300}, headers=H(ta))
    before = client.get("/me", headers=H(tb)).json()["coins"]
    r = buy(tb, "cv_moon")
    assert r.status_code == 200, r.text
    assert r.json()["balance"] == before - 80 and r.json()["item"]["owned"] is True
    assert buy(tb, "cv_moon").status_code == 409
    assert buy(tb, "fx_snow").json()["balance"] == before - 80      # бесплатный
    assert buy(tb, "cv_soon").status_code == 410
    # лимит: 1 штука
    assert buy(tb, "fr_fire").status_code == 200
    client.post(f"/admin/users/{ids['c']}/coins", json={"amount": 300}, headers=H(ta))
    assert buy(tc, "fr_fire").status_code == 410
    # нельзя надеть чужое
    assert client.post("/shop/items/cv_moon/equip", headers=H(tc)).status_code == 403
    # надеваем: видео-обложка из магазина работает без Premium
    for iid in ("cv_moon", "fr_fire", "fx_snow"):
        assert client.post(f"/shop/items/{iid}/equip", headers=H(tb)).status_code == 200
    me = client.get("/me", headers=H(tb)).json()
    assert me["cover_url"] == "/media/shop/x.mp4" and me["cover_kind"] == "video"
    assert me["frame"]["url"] == "/media/shop/f.webp" and me["profile_fx"]["id"] == "fx_snow"
    prof = client.get(f"/users/{ids['b']}", headers=H(tc)).json()
    assert prof["frame"]["id"] == "fr_fire" and prof["profile_fx"]["url"] == "/media/shop/s.webp"
    inv = client.get("/shop/inventory", headers=H(tb)).json()
    assert {x["id"] for x in inv["items"]} == {"cv_moon", "fr_fire", "fx_snow"}
    assert inv["equipped"]["frame"] == "fr_fire"
    assert [x for x in inv["items"] if x["id"] == "fx_snow"][0]["source"] == "free"
    # снять рамку
    assert client.post("/shop/unequip", json={"kind": "frame"}, headers=H(tb)).json()["me"]["frame"] is None
    # своя обложка снимает магазинную
    client.patch("/me", json={"cover_url": ""}, headers=H(tb))
    assert client.get("/me", headers=H(tb)).json()["cover_item"] is None
    # подарок другу: списывается с дарителя, предмет у получателя
    cb = client.get("/me", headers=H(tc)).json()["coins"]
    r = buy(tc, "cv_moon", to_user_id=ids["a"], text="с праздником")
    assert r.status_code == 200 and r.json()["gift"] is True and r.json()["balance"] == cb - 80
    assert buy(tc, "cv_moon", to_user_id=ids["a"]).status_code == 409
    assert buy(tc, "fx_snow", to_user_id=ids["a"]).status_code == 400   # бесплатный
    inv_a = client.get("/shop/inventory", headers=H(ta)).json()["items"]
    assert inv_a[0]["id"] == "cv_moon" and inv_a[0]["source"] == "gift"
    # карточка товара + похожие
    d = client.get("/shop/items/cv_moon", headers=H(tc)).json()
    assert d["sold"] == 2 and isinstance(d["similar"], list)
    # удаление купленного — только снятие с продажи; у владельцев остаётся
    assert client.delete("/admin/shop/items/cv_moon", headers=H(ta)).json()["hidden"] is True
    assert "cv_moon" not in [x["id"] for x in srch()["items"]]
    assert client.get("/shop/items/cv_moon", headers=H(tb)).status_code == 200
    assert client.delete("/admin/shop/items/cv_soon", headers=H(ta)).json()["hidden"] is False
    # Premium: обои бесплатно
    client.post(f"/admin/users/{ids['c']}/premium", json={"days": 30}, headers=H(ta))
    w = [x for x in srch(kind="wallpaper")["items"]]
    cw = client.get("/shop/items/wp_city", headers=H(tc)).json()
    assert cw["my_price"] == 0 and cw["final_price"] == 40
    cb = client.get("/me", headers=H(tc)).json()["coins"]
    assert buy(tc, "wp_city").json()["balance"] == cb
    assert w


def test_shop_import_pack(client, users):
    """Пак-архив: коллекция, товары с медиа и подарки одним файлом."""
    import io
    import json
    import zipfile
    ta = tok(users, "a")
    spec = {
        "collections": [{"id": "space", "title": "Космос", "banner": "banner.jpg",
                         "colors": ["#000000", "#334455"]}],
        "items": [
            {"id": "cv_nebula", "kind": "cover", "title": "Туманность", "price": 120,
             "collection": "space", "media": "nebula.mp4", "preview": "nebula.jpg"},
            {"id": "fr_orbit", "kind": "frame", "title": "Орбита", "price": 60,
             "media": "orbit.webp", "featured": True},
        ],
        "gifts": [{"id": "hw_skull", "title": "Череп", "price": 70, "rarity": "epic",
                   "image": "skull.png"}],
    }
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("pack/shop.json", json.dumps(spec, ensure_ascii=False))
        for n in ("banner.jpg", "nebula.mp4", "nebula.jpg", "orbit.webp", "skull.png"):
            z.writestr("pack/" + n, b"data-" + n.encode())
    r = client.post("/admin/shop/import", files={"file": ("p.zip", buf.getvalue(), "application/zip")},
                    headers=H(ta))
    assert r.status_code == 200, r.text
    assert r.json() == {"collections": 1, "items": 2, "gifts": 1, "files": 5}
    items = {x["id"]: x for x in client.get("/admin/shop/items", headers=H(ta)).json()}
    assert items["cv_nebula"]["media_kind"] == "video"
    assert items["cv_nebula"]["preview_url"].endswith(".jpg")
    assert client.get(items["fr_orbit"]["media_url"]).content == b"data-orbit.webp"
    home = client.get("/shop", headers=H(ta)).json()
    assert any(b["id"] == "space" and b["banner_url"] for b in home["banners"])
    assert [x["id"] for x in home["featured"]] == ["fr_orbit"]
    cat = client.get("/gifts/catalog", headers=H(ta)).json()["gifts"]
    assert any(g["id"] == "hw_skull" and g.get("image_url") for g in cat)
    # повторный импорт без медиа обновляет поля, но не стирает картинку
    buf2 = io.BytesIO()
    spec2 = {"items": [{"id": "fr_orbit", "kind": "frame", "title": "Орбита 2", "price": 30}]}
    with zipfile.ZipFile(buf2, "w") as z:
        z.writestr("shop.json", json.dumps(spec2))
    assert client.post("/admin/shop/import", files={"file": ("p.zip", buf2.getvalue())},
                       headers=H(ta)).status_code == 200
    it = [x for x in client.get("/admin/shop/items", headers=H(ta)).json() if x["id"] == "fr_orbit"][0]
    assert it["title"] == "Орбита 2" and it["media_url"] == items["fr_orbit"]["media_url"]
    # ошибки
    bad = io.BytesIO()
    with zipfile.ZipFile(bad, "w") as z:
        z.writestr("shop.json", json.dumps({"items": [{"id": "x1", "kind": "cover", "title": "x",
                                                       "media": "nope.mp4"}]}))
    assert client.post("/admin/shop/import", files={"file": ("p.zip", bad.getvalue())},
                       headers=H(ta)).status_code == 400
    assert client.post("/admin/shop/import", files={"file": ("p.zip", b"not zip")},
                       headers=H(ta)).status_code == 400
    # загрузка медиа по одному
    r = client.post("/admin/shop/media", files={"file": ("a.webp", b"RIFFxxxxWEBP")}, headers=H(ta))
    assert r.status_code == 200 and r.json()["kind"] == "image"
    assert client.post("/admin/shop/media", files={"file": ("a.exe", b"MZ")},
                       headers=H(ta)).status_code == 400
