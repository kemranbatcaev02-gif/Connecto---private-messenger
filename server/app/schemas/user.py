from datetime import datetime

from pydantic import BaseModel, EmailStr, Field, ConfigDict


class UserCreate(BaseModel):
    username: str = Field(min_length=3, max_length=32, pattern=r"^[a-zA-Z0-9_]+$")
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(min_length=1, max_length=64)
    code: str | None = None  # код подтверждения почты (если включено)
    device_id: str | None = None   # id устройства (запомнить как доверенное)
    platform: str | None = None    # платформа/имя устройства


class UserLogin(BaseModel):
    login: str
    password: str


class HandleUpdate(BaseModel):
    handle: str = Field(min_length=3, max_length=32, pattern=r"^[a-zA-Z0-9_]+$")


class ProfileUpdate(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=64)
    last_name: str | None = Field(default=None, max_length=64)
    bio: str | None = Field(default=None, max_length=300)
    phone: str | None = Field(default=None, max_length=32)
    birthday: str | None = Field(default=None, max_length=20)
    avatar_url: str | None = Field(default=None, max_length=512)
    lastseen_privacy: str | None = Field(default=None, pattern=r"^(all|contacts|none)$")
    cover_url: str | None = Field(default=None, max_length=512)      # "" — убрать
    cover_kind: str | None = Field(default=None, pattern=r"^(image|video)$")
    emoji_status: str | None = Field(default=None, max_length=16)    # "" — убрать
    avatar_ring: str | None = Field(default=None, pattern=r"^(none|accent|rainbow|gold|aurora)$")


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    username: str
    handle: str | None = None
    email: EmailStr
    display_name: str
    last_name: str | None = None
    bio: str | None = None
    phone: str | None = None
    birthday: str | None = None
    avatar_url: str | None = None
    lastseen_privacy: str = "all"
    banned: bool = False
    is_admin: bool = False
    created_at: datetime


class UserPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    username: str
    handle: str | None = None
    display_name: str
    avatar_url: str | None = None


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
