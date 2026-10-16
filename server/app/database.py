from datetime import timezone

from sqlalchemy import create_engine, DateTime
from sqlalchemy.orm import sessionmaker, declarative_base
from sqlalchemy.types import TypeDecorator

from app.config import settings

# SQLite требует этот флаг при работе в многопоточном сервере.
connect_args = (
    {"check_same_thread": False}
    if settings.database_url.startswith("sqlite")
    else {}
)

engine = create_engine(settings.database_url, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class UTCDateTime(TypeDecorator):
    """Время всегда в UTC и всегда с поясом.

    SQLite не хранит часовой пояс: без этого из базы приходило «10:00» без пометки
    UTC, и приложение показывало его как местное — на 3 часа мимо (Москва = UTC+3).
    """

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
