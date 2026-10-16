"""Выложить новую версию: у всех, у кого Connecto стоит, появится «Доступно обновление».

Запускает build_all.ps1 -Release (или -Publish) сам, после того как положит файлы
в /opt/connecto-server/downloads. Можно и вручную:
  python3 /opt/connecto-server/publish_release.py --version 1.0.0 --build 7 --apk --exe
"""
import argparse
import json
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
FILE = os.path.join(ROOT, "app_version.json")
BASE = "http://193.233.112.115:8000"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", required=True, type=int)
    ap.add_argument("--apk", action="store_true")
    ap.add_argument("--exe", action="store_true")
    ap.add_argument("--notes", default="")
    a = ap.parse_args()

    try:
        with open(FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}
    notes = a.notes or f"Connecto {a.version}: исправления и улучшения. Обнови, чтобы всё работало стабильно."

    if a.apk:
        if not os.path.isfile(os.path.join(ROOT, "downloads", "Connecto.apk")):
            raise SystemExit("нет downloads/Connecto.apk")
        data.update({"build": a.build, "version": a.version,
                     "url_direct": f"{BASE}/download/Connecto.apk", "notes": notes})
        data.setdefault("url_telegram", "")
    if a.exe:
        if not os.path.isfile(os.path.join(ROOT, "downloads", "Connecto-Setup.exe")):
            raise SystemExit("нет downloads/Connecto-Setup.exe")
        win = data.get("windows") if isinstance(data.get("windows"), dict) else {}
        win.update({"build": a.build, "version": a.version,
                    "url": f"{BASE}/download/Connecto-Setup.exe", "notes": notes})
        data["windows"] = win

    tmp = FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, FILE)
    print(f"RELEASE-OK {a.version} (сборка {a.build})"
          + (" · APK" if a.apk else "") + (" · ПК" if a.exe else ""))


if __name__ == "__main__":
    main()
