import os
import re
import uuid

from fastapi import APIRouter, Depends, UploadFile, File, HTTPException

from app.deps import get_current_user
from app.models.user import User
from app.privacy import is_premium

router = APIRouter(tags=["upload"])

MEDIA_DIR = "media"
os.makedirs(MEDIA_DIR, exist_ok=True)

FREE_LIMIT = 100 * 1024 * 1024       # 100 МБ
PREMIUM_LIMIT = 500 * 1024 * 1024    # 500 МБ
CHUNK = 1024 * 1024


@router.post("/upload")
async def upload(file: UploadFile = File(...),
                 current_user: User = Depends(get_current_user)):
    limit = PREMIUM_LIMIT if is_premium(current_user) else FREE_LIMIT
    ext = os.path.splitext(file.filename or "")[1][:10].lower()
    if not re.fullmatch(r"\.[a-z0-9]{1,9}", ext):
        ext = ""
    name = f"{uuid.uuid4().hex}{ext}"
    path = os.path.join(MEDIA_DIR, name)
    size = 0
    try:
        with open(path, "wb") as f:
            while True:
                chunk = await file.read(CHUNK)
                if not chunk:
                    break
                size += len(chunk)
                if size > limit:
                    raise HTTPException(
                        status_code=413,
                        detail=f"Файл больше {limit // (1024 * 1024)} МБ"
                               + ("" if limit == PREMIUM_LIMIT else " (с Premium — до 500 МБ)"))
                f.write(chunk)
    except HTTPException:
        try:
            os.remove(path)
        except OSError:
            pass
        raise
    return {"url": f"/media/{name}", "file_name": file.filename or name, "size": size}
