# Деплой Connecto API на VPS (Ubuntu 24.04)

## 0. Что нужно
- VPS с публичным IPv4, Ubuntu 24.04, доступ по SSH (root или sudo).
- Локально на ПК — код в `C:\connecto\server`.

## 1. Залить код на сервер (с ПК, PowerShell)
В Windows есть встроенный OpenSSH. Замени `IP` на адрес VPS:
```powershell
scp -r C:\connecto\server root@IP:/opt/connecto-server
```
(Если папки `/opt` нет прав — сначала `ssh root@IP "mkdir -p /opt"`.)

## 2. На сервере (по SSH: `ssh root@IP`)
```bash
apt update && apt install -y python3-venv python3-pip
cd /opt/connecto-server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## 3. Настроить .env
```bash
cat > /opt/connecto-server/.env << 'ENV'
DATABASE_URL=sqlite:///./connecto.db
JWT_SECRET=ЗАМЕНИ_НА_ДЛИННУЮ_СЛУЧАЙНУЮ_СТРОКУ
ENV
```
Сгенерировать секрет: `python3 -c "import secrets; print(secrets.token_urlsafe(48))"`

## 4. Проверить запуск
```bash
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000
```
Открой в браузере `http://IP:8000/docs` — должен открыться Swagger. Ctrl+C чтобы остановить.

## 5. Автозапуск через systemd
```bash
cp /opt/connecto-server/deploy/connecto.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now connecto
systemctl status connecto        # должно быть active (running)
```

## 6. Открыть порт
```bash
ufw allow 22/tcp
ufw allow 8000/tcp
ufw --force enable
```

## 7. (Позже) Домен + HTTPS — бесплатно
Если появится домен, направь его A-записью на IP, затем:
```bash
apt install -y nginx certbot python3-certbot-nginx
# конфиг nginx: proxy_pass http://127.0.0.1:8000; (+ проброс WebSocket-заголовков для /ws)
certbot --nginx -d ТВОЙ_ДОМЕН
```
Тогда адрес станет `https://ТВОЙ_ДОМЕН`, а WebSocket — `wss://ТВОЙ_ДОМЕН/ws`.

## Обновление кода потом
```powershell
scp -r C:\connecto\server\app root@IP:/opt/connecto-server/
```
```bash
systemctl restart connecto
```
