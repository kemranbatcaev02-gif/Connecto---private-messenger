from pydantic import BaseModel, Field


class ChatCreate(BaseModel):
    type: str = Field(pattern=r"^(direct|group|channel)$")
    title: str | None = Field(default=None, max_length=128)
    description: str | None = Field(default=None, max_length=500)
    handle: str | None = Field(default=None, max_length=32)
    avatar_url: str | None = None
    member_ids: list[str] = []


class MessageCreate(BaseModel):
    text: str = Field(default="", max_length=4000)
    kind: str = Field(
        default="text",
        pattern=r"^(text|image|video|file|voice|round|location|contact)$")
    media_url: str | None = None
    file_name: str | None = None
    reply_to_id: str | None = None
    forwarded_from: str | None = None
    effect: str | None = Field(default=None, max_length=16)
    silent: bool = False
    open_at: int | None = None          # epoch ms — капсула времени
    story_id: str | None = None         # ответ на историю
    enc: str | None = Field(default=None, max_length=60000)   # сквозное шифрование


class MessageEdit(BaseModel):
    text: str = Field(default="", max_length=4000)
    enc: str | None = Field(default=None, max_length=60000)


class PinUpdate(BaseModel):
    pinned: bool = True
