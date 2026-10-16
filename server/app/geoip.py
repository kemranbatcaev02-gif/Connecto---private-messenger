"""Определение примерного города по IP (для писем о входе).
Использует бесплатный ip-api.com. Без ключа, с таймаутом и мягким фолбэком."""
import json
import urllib.request

_cache: dict[str, str] = {}


def city_by_ip(ip: str | None) -> str:
    if not ip:
        return ""
    # локальные адреса не геолоцируются
    if ip.startswith(("127.", "10.", "192.168.", "172.")) or ip == "::1":
        return ""
    if ip in _cache:
        return _cache[ip]
    result = ""
    try:
        url = (f"http://ip-api.com/json/{ip}"
               "?fields=status,country,city&lang=ru")
        with urllib.request.urlopen(url, timeout=4) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        if data.get("status") == "success":
            city = (data.get("city") or "").strip()
            country = (data.get("country") or "").strip()
            result = ", ".join(x for x in (city, country) if x)
    except Exception:
        result = ""
    _cache[ip] = result
    return result
