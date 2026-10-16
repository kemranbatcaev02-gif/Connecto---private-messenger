#!/usr/bin/env bash
# Connecto: установка TURN-сервера (coturn) для звонков. Запускать один раз:
#   bash /opt/connecto-server/setup_turn.sh
# Что делает: ставит coturn, придумывает секрет, пишет его в .env сервера
# (TURN_SECRET) и в /etc/turnserver.conf, открывает порты и перезапускает всё.
set -e
cd /opt/connecto-server

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y coturn openssl curl

SECRET=$(grep -s '^TURN_SECRET=' .env | cut -d= -f2 || true)
if [ -z "$SECRET" ]; then
  SECRET=$(openssl rand -hex 24)
  printf '\nTURN_SECRET=%s\n' "$SECRET" >> .env
fi

IP=$(curl -s --max-time 5 https://api.ipify.org || true)
[ -z "$IP" ] && IP=$(hostname -I | awk '{print $1}')

cat > /etc/turnserver.conf <<CONF
listening-port=3478
fingerprint
use-auth-secret
static-auth-secret=$SECRET
realm=connecto
external-ip=$IP
min-port=49160
max-port=49400
no-multicast-peers
no-cli
no-tlsv1
no-tlsv1_1
# не пускаем трафик во внутренние сети сервера
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
total-quota=300
stale-nonce=600
simple-log
log-file=/var/log/turnserver.log
CONF

if [ -f /etc/default/coturn ]; then
  sed -i 's/^#\?TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn
fi
systemctl enable coturn >/dev/null 2>&1 || true
systemctl restart coturn

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow 3478/tcp
  ufw allow 3478/udp
  ufw allow 49160:49400/udp
fi

systemctl restart connecto
echo ""
echo "TURN готов: $IP:3478 — звонки будут проходить даже через мобильный интернет."
systemctl --no-pager --lines=0 status coturn | head -3
