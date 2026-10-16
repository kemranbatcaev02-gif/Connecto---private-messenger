from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Строка подключения к БД. Сейчас SQLite (файл connecto.db рядом).
    # Для перехода на PostgreSQL достаточно поменять эту строку в .env, например:
    # postgresql+psycopg2://user:password@localhost:5432/connecto
    database_url: str = "sqlite:///./connecto.db"

    # Секрет для подписи JWT. В .env обязательно свой длинный случайный.
    jwt_secret: str = "CHANGE_ME_dev_secret"
    jwt_algorithm: str = "HS256"
    # access живёт 30 дней, refresh — 180. Сеанс можно завершить в любой момент
    # (Настройки → Устройства), тогда оба токена сразу перестают работать.
    access_token_expire_minutes: int = 60 * 24 * 30
    refresh_token_expire_days: int = 180
    # адрес сервера для ссылок-приглашений и картинок в пушах
    public_base: str = "https://connectomes.duckdns.org"

    # Звонки: свой TURN-сервер (coturn с use-auth-secret). Пока секрет пустой —
    # звонки идут только напрямую (P2P) через STUN; за «строгим» NAT мобильных
    # операторов без TURN соединение может не установиться.
    turn_secret: str = ""
    turn_host: str = "193.233.112.115"
    turn_port: int = 3478

    # Внешние бесплатные API (github.com/public-apis/public-apis).
    # GIF: ключ GIPHY (developers.giphy.com → Create an App → API). Без ключа —
    # только аниме-реакции nekos.best (тоже бесплатно, без ключа).
    giphy_key: str = ""
    # Перевод: свой LibreTranslate (необязательно). Без него — Google (gtx) и MyMemory.
    libretranslate_url: str = ""
    libretranslate_key: str = ""
    mymemory_email: str = ""        # с почтой у MyMemory лимит 50 000 символов в день
    # Музыка для историй: страна каталога iTunes (превью 30 с), запасной — Deezer
    music_country: str = "US"


settings = Settings()

# ── Админы приложения ──
# Аккаунты с этими email автоматически получают права админа
# (список пользователей, бан, удаление). Регистрируйся с любой из этих почт.
ADMIN_EMAILS = {
    "kemranbatcaev02@gmail.com",
    "ebekkuev09@yandex.ru",
}


def is_admin_email(email: str | None) -> bool:
    return bool(email) and email.strip().lower() in ADMIN_EMAILS


# ── Покупка коинов и Premium, пока нет онлайн-оплаты ──
# Кнопки «Написать в Connecto» и «Написать в Telegram» в приложении ведут сюда.
# SELLER_EMAIL — почта аккаунта в Connecto, которому пишут покупатели (личка).
SELLER_EMAIL = "kemranbatcaev02@gmail.com"
SELLER_TELEGRAM = "kemq78"   # без @
