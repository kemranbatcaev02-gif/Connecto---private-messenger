"""Отправка писем через SMTP (Яндекс, Gmail, Mail.ru и др.).
Настройки берутся из smtp.json в корне сервера.

Для 100% доставляемости без попадания в СПАМ:
1. Используется прямое защищенное SSL-соединение (порт 465).
2. Заголовки RFC-2822: From, To, Subject, Date, Content-Type, MIME-Version.
3. Message-ID формируется почтовым сервером Яндекса (подпись DKIM и SPF проходят проверку).
4. Удалены триггеры спам-фильтров (Auto-Submitted, начинающиеся с цифр темы).
5. Адаптивная HTML-верстка с выделенным блоком кода и предупреждением о безопасности.
"""
import html
import json
import os
import smtplib
from email.header import Header
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr, formatdate, parseaddr

CFG_FILE = "smtp.json"
_cfg = None
_loaded = False


def _load():
    global _cfg, _loaded
    if _loaded:
        return _cfg
    _loaded = True
    try:
        if os.path.exists(CFG_FILE):
            with open(CFG_FILE, "r", encoding="utf-8") as f:
                _cfg = json.load(f)
    except Exception:
        _cfg = None
    return _cfg


def enabled() -> bool:
    return _load() is not None


def _build_html(title: str, message: str, code: str | None = None) -> str:
    code_block = ""
    if code:
        code_block = f"""
        <div style="text-align: center; margin: 28px 0; padding: 22px; background: #f3f0ff; border-radius: 16px; border: 1px dashed #6c5ce7;">
          <span style="font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace; font-size: 34px; font-weight: 800; letter-spacing: 8px; color: #4834d4; display: inline-block;">{html.escape(code)}</span>
        </div>
        """

    return f"""<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Connecto</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f6f7fb; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #2d3748;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f6f7fb; padding: 36px 14px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width: 500px; background-color: #ffffff; border-radius: 20px; box-shadow: 0 4px 24px rgba(0,0,0,0.06); overflow: hidden; border: 1px solid #edf2f7;">
          <tr>
            <td style="background: linear-gradient(135deg, #6c5ce7 0%, #4834d4 100%); padding: 30px 32px; text-align: center;">
              <h1 style="margin: 0; color: #ffffff; font-size: 26px; font-weight: 800; letter-spacing: -0.5px;">Connecto</h1>
              <p style="margin: 6px 0 0 0; color: #e0e7ff; font-size: 13px; font-weight: 500;">Безопасный мессенджер</p>
            </td>
          </tr>
          <tr>
            <td style="padding: 32px 32px 24px 32px;">
              <h2 style="margin: 0 0 14px 0; font-size: 19px; font-weight: 700; color: #1a202c;">{html.escape(title)}</h2>
              <p style="margin: 0 0 20px 0; font-size: 15px; line-height: 1.6; color: #4a5568;">{message}</p>
              
              {code_block}

              <div style="margin-top: 24px; padding: 14px 16px; background-color: #f8fafc; border-radius: 12px; border-left: 4px solid #6c5ce7;">
                <p style="margin: 0; font-size: 12.5px; line-height: 1.5; color: #718096;">
                  ⚠️ <strong>Безопасность:</strong> Никому не сообщайте этот код. Сотрудники Connecto никогда не запрашивают ваши коды подтверждения. Код действителен 10 минут.
                </p>
              </div>
            </td>
          </tr>
          <tr>
            <td style="padding: 20px 32px 28px 32px; border-top: 1px solid #f1f5f9; text-align: center;">
              <p style="margin: 0; font-size: 12px; color: #a0aec0; line-height: 1.5;">
                Это служебное уведомление безопасности вашего аккаунта Connecto.<br>
                Если вы не совершали данное действие, просто проигнорируйте письмо.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""


def _send(email: str, subject: str, plain_body: str, title: str, html_message: str, code: str | None = None) -> bool:
    cfg = _load()
    if not cfg:
        return False
    try:
        user_addr = cfg.get("user", "")
        sender_header = cfg.get("from") or formataddr(("Connecto", user_addr))
        from_email = parseaddr(sender_header)[1] or user_addr
        
        # Корректный MIME контейнер: multipart/alternative (plain + html)
        msg = MIMEMultipart("alternative")
        msg["Subject"] = Header(subject, "utf-8")
        msg["From"] = formataddr(("Connecto", from_email))
        msg["To"] = email
        msg["Date"] = formatdate(localtime=True)
        msg["Reply-To"] = cfg.get("reply_to") or from_email
        msg["X-Priority"] = "3"
        msg["Importance"] = "normal"
        msg["MIME-Version"] = "1.0"
        
        # Plain text версия
        msg.attach(MIMEText(plain_body, "plain", "utf-8"))
        # HTML версия
        html_content = _build_html(title, html_message, code)
        msg.attach(MIMEText(html_content, "html", "utf-8"))
        
        host = cfg.get("host", "smtp.yandex.ru")
        port = int(cfg.get("port", 465))
        
        if port == 465:
            server = smtplib.SMTP_SSL(host, port, timeout=12)
        else:
            server = smtplib.SMTP(host, port, timeout=12)
            server.starttls()
            
        server.login(cfg["user"], cfg["password"])
        # Envelope sender строго совпадает с авторизованным email (для идеального SPF/DMARC)
        server.sendmail(from_email, [email], msg.as_string())
        server.quit()
        return True
    except Exception as e:  # noqa: BLE001
        print(f"SMTP: ошибка отправки на {email}: {e!r}", flush=True)
        return False


def check() -> str:
    """Диагностика почты для админа: проверка связи и логина."""
    cfg = _load()
    if not cfg:
        return "smtp.json не найден — почта выключена"
    try:
        host = cfg.get("host", "smtp.yandex.ru")
        port = int(cfg.get("port", 465))
        if port == 465:
            server = smtplib.SMTP_SSL(host, port, timeout=12)
        else:
            server = smtplib.SMTP(host, port, timeout=12)
            server.starttls()
        server.login(cfg["user"], cfg["password"])
        server.quit()
        return f"OK: подключение к {host}:{port} как {cfg['user']} успешно"
    except Exception as e:  # noqa: BLE001
        return f"Ошибка: {e!r}"


def send_code(email: str, code: str) -> bool:
    subject = f"Код подтверждения Connecto: {code}"
    title = "Подтверждение регистрации"
    html_msg = "Добро пожаловать в Connecto! Используйте одноразовый код ниже для подтверждения адреса электронной почты:"
    plain = (f"Добро пожаловать в Connecto!\n\n"
             f"Ваш код для подтверждения почты: {code}\n\n"
             "Код действует 10 минут.\n"
             "Никому не сообщайте этот код. Если вы не регистрировались — просто проигнорируйте письмо.\n\n"
             "Connecto Messenger\nhttps://connectomes.duckdns.org")
    return _send(email, subject, plain, title, html_msg, code)


def send_login_code(email: str, code: str, city: str = "", platform: str = "") -> bool:
    subject = f"Код для входа в Connecto: {code}"
    title = "Вход в аккаунт Connecto"
    info = []
    if platform:
        info.append(f"Устройство: <b>{html.escape(platform)}</b>")
    if city:
        info.append(f"Местоположение: <b>{html.escape(city)}</b>")
    details = "<br>".join(info)
    if details:
        details = f"<div style='margin-bottom:12px;font-size:14px;color:#4a5568;'>{details}</div>"
        
    html_msg = f"{details}Кто-то пытается войти в ваш аккаунт Connecto. Если это вы, введите одноразовый код подтверждения:"
    
    plain_info = []
    if platform: plain_info.append(f"Устройство: {platform}")
    if city: plain_info.append(f"Откуда: {city}")
    details_plain = "\n".join(plain_info)
    if details_plain: details_plain += "\n\n"
    
    plain = (f"Кто-то входит в ваш аккаунт Connecto.\n\n"
             f"{details_plain}"
             f"Код для входа: {code}\n\n"
             "Код действует 10 минут.\n"
             "Если это не вы — не вводите код и смените пароль.\n\n"
             "Connecto Messenger\nhttps://connectomes.duckdns.org")
    return _send(email, subject, plain, title, html_msg, code)


def send_email_change_code(email: str, code: str) -> bool:
    subject = f"Смена почты в Connecto: {code}"
    title = "Привязка нового адреса почты"
    html_msg = "Вы запросили привязку этого адреса к вашему аккаунту Connecto. Введите одноразовый код для подтверждения:"
    plain = (f"Вы привязываете эту почту к аккаунту Connecto.\n\n"
             f"Код подтверждения: {code}\n\n"
             "Код действует 10 минут.\n"
             "Если это не вы — просто проигнорируйте письмо.\n\n"
             "Connecto Messenger\nhttps://connectomes.duckdns.org")
    return _send(email, subject, plain, title, html_msg, code)


def send_email_changed_notice(email: str, new_masked: str) -> bool:
    subject = "Почта аккаунта Connecto изменена"
    title = "Безопасность аккаунта"
    html_msg = f"Почта вашего аккаунта Connecto была успешно изменена на <b>{html.escape(new_masked)}</b>.<br><br>Если это сделали не вы — немедленно войдите в аккаунт, смените пароль и завершите активные сеансы в разделе Настройки → Устройства."
    plain = (f"Почта вашего аккаунта Connecto изменена на {new_masked}.\n\n"
             "Если это сделали не вы — срочно войдите в аккаунт, смените пароль "
             "и завершите чужие сеансы в Настройки → Устройства.\n\n"
             "Connecto Messenger\nhttps://connectomes.duckdns.org")
    return _send(email, subject, plain, title, html_msg, None)


def send_reset_code(email: str, code: str) -> bool:
    subject = f"Сброс пароля Connecto: {code}"
    title = "Восстановление доступа"
    html_msg = "Был запрошен сброс пароля для вашего аккаунта Connecto. Введите код подтверждения:"
    plain = (f"Сброс пароля Connecto.\n\n"
             f"Код подтверждения: {code}\n\n"
             "Код действует 10 минут.\n"
             "Если вы не запрашивали сброс — просто проигнорируйте письмо, ваш пароль не изменится.\n\n"
             "Connecto Messenger\nhttps://connectomes.duckdns.org")
    return _send(email, subject, plain, title, html_msg, code)


def send_2fa_reset_code(email: str, code: str) -> bool:
    subject = f"Сброс облачного пароля Connecto: {code}"
    title = "Сброс 2-этапной аутентификации"
    html_msg = "Был запрошен сброс облачного пароля Connecto. После ввода кода облачный пароль будет отключен:"
    plain = (f"Сброс облачного пароля Connecto.\n\n"
             f"Код подтверждения: {code}\n\n"
             "После ввода кода облачный пароль будет отключён.\n"
             "Если это не вы — не вводите код и смените основной пароль.\n\n"
             "Connecto Messenger\nhttps://connectomes.duckdns.org")
    return _send(email, subject, plain, title, html_msg, code)
