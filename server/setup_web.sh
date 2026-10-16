#!/usr/bin/env bash
# Connecto: веб-версия по HTTPS (сайт + API на одном адресе). Запускать один раз:
#   bash /opt/connecto-server/setup_web.sh ИМЯ ТОКЕН
# ИМЯ  — поддомен с duckdns.org (для connecto-kema.duckdns.org — это connecto-kema)
# ТОКЕН — token со страницы duckdns.org после входа
#
# Что делает:
#   1) раз в 5 минут сообщает DuckDNS адрес сервера (домен всегда смотрит сюда);
#   2) ставит Caddy — он сам получает и продлевает сертификат Let's Encrypt;
#   3) https://ИМЯ.duckdns.org/      — сайт (файлы из /opt/connecto-web)
#      https://ИМЯ.duckdns.org/api/  — наш сервер (порт 8000), вместе с WebSocket.
# Приложения на телефоне и ПК продолжают ходить на http://IP:8000 — им ничего не меняется.
set -e

SUB="${1%%.duckdns.org}"
TOKEN="$2"
if [ -z "$SUB" ] || [ -z "$TOKEN" ]; then
  echo "Нужно так: bash setup_web.sh ИМЯ ТОКЕН   (ИМЯ и ТОКЕН — с сайта duckdns.org)"
  exit 1
fi
DOMAIN="$SUB.duckdns.org"
WEB=/opt/connecto-web

echo "==> DuckDNS: $DOMAIN → этот сервер"
mkdir -p /opt/duckdns
cat > /opt/duckdns/duck.sh <<EOF
#!/usr/bin/env bash
curl -s --max-time 20 "https://www.duckdns.org/update?domains=$SUB&token=$TOKEN&ip=" -o /opt/duckdns/duck.log
EOF
chmod 700 /opt/duckdns/duck.sh
( crontab -l 2>/dev/null | grep -v '/opt/duckdns/duck.sh'; echo '*/5 * * * * /opt/duckdns/duck.sh >/dev/null 2>&1' ) | crontab -
/opt/duckdns/duck.sh
if [ "$(cat /opt/duckdns/duck.log 2>/dev/null)" != "OK" ]; then
  echo "DuckDNS ответил не OK — проверь ИМЯ и ТОКЕН на duckdns.org"
  exit 1
fi

echo "==> Проверяю, что порты 80/443 свободны"
BUSY=$(ss -ltnp 2>/dev/null | awk '$4 ~ /:(80|443)$/' | grep -v caddy || true)
if [ -n "$BUSY" ]; then
  echo "Порты 80/443 уже заняты другой программой:"
  echo "$BUSY"
  echo "Останови её (например: systemctl disable --now nginx) и запусти скрипт снова."
  exit 1
fi

echo "==> Ставлю Caddy"
if ! command -v caddy >/dev/null 2>&1; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y caddy
fi

mkdir -p "$WEB"
if [ ! -f "$WEB/index.html" ]; then
  cat > "$WEB/index.html" <<'HTML'
<!doctype html><meta charset="utf-8"><title>Connecto</title>
<body style="background:#16131f;color:#ddd;font-family:sans-serif;display:grid;place-items:center;height:100vh">
<p>HTTPS работает. Осталось залить сайт: build_all.ps1 -Web -Upload</p></body>
HTML
fi

cat > /etc/caddy/Caddyfile <<CONF
$DOMAIN {
	encode zstd gzip

	# наш сервер: /api/... → 127.0.0.1:8000/... (и WebSocket /api/ws)
	handle_path /api/* {
		reverse_proxy 127.0.0.1:8000
	}

	# сайт (Flutter web)
	handle {
		root * $WEB
		# index.html и загрузчик — всегда свежие, чтобы после выкладки сразу была новая версия
		# (у main.dart.js и манифестов имя не меняется между сборками — браузер сверяет их по ETag)
		@fresh path / /index.html /flutter_bootstrap.js /flutter_service_worker.js /version.json /manifest.json /main.dart.* /assets/AssetManifest* /assets/FontManifest.json /canvaskit/*
		header @fresh Cache-Control "no-cache"
		try_files {path} /index.html
		file_server
	}

	header {
		Strict-Transport-Security "max-age=31536000"
		X-Content-Type-Options "nosniff"
		Referrer-Policy "strict-origin-when-cross-origin"
		Permissions-Policy "camera=(self), microphone=(self), display-capture=(self), geolocation=(self)"
	}
}
CONF

caddy fmt --overwrite /etc/caddy/Caddyfile >/dev/null 2>&1 || true
systemctl enable caddy >/dev/null 2>&1 || true
systemctl restart caddy

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 443/udp
fi

echo ""
echo "Жду сертификат (до минуты)..."
for i in $(seq 1 30); do
  if curl -s --max-time 5 -o /dev/null "https://$DOMAIN/api/app_version"; then
    echo ""
    echo "Готово! Сайт: https://$DOMAIN"
    echo "Проверка API: https://$DOMAIN/api/app_version"
    exit 0
  fi
  sleep 2
done
echo "Сертификат пока не выдан. Посмотри журнал: journalctl -u caddy --no-pager -n 40"
