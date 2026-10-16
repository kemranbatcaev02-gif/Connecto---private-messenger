"""Коды подтверждения (в памяти, TTL 10 минут, не больше 5 попыток на код)
и простая защита от подбора пароля."""
import random
import time

_pending: dict[str, list] = {}   # key -> [code, expires_at, attempts]
_TTL = 600  # 10 минут
_MAX_ATTEMPTS = 5


def gen_and_store(key: str) -> str:
    code = f"{random.SystemRandom().randint(0, 999999):06d}"
    _pending[key.lower()] = [code, time.time() + _TTL, 0]
    return code


def check(key: str, code: str | None) -> bool:
    if not code:
        return False
    k = key.lower()
    v = _pending.get(k)
    if not v:
        return False
    saved, exp, attempts = v
    if time.time() > exp or attempts >= _MAX_ATTEMPTS:
        _pending.pop(k, None)
        return False
    if saved == code.strip():
        _pending.pop(k, None)
        return True
    v[2] = attempts + 1
    if v[2] >= _MAX_ATTEMPTS:
        _pending.pop(k, None)
    return False


# ── ограничение попыток входа: 10 ошибок за 15 минут → пауза ──
_fails: dict[str, list[float]] = {}
_WINDOW = 15 * 60
_MAX_FAILS = 10


def too_many(key: str) -> bool:
    now = time.time()
    arr = [t for t in _fails.get(key.lower(), []) if now - t < _WINDOW]
    _fails[key.lower()] = arr
    return len(arr) >= _MAX_FAILS


def fail(key: str) -> None:
    _fails.setdefault(key.lower(), []).append(time.time())


def reset(key: str) -> None:
    _fails.pop(key.lower(), None)
