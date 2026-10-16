from fastapi import WebSocket


class ConnectionManager:
    """Держит активные WebSocket-соединения по user_id."""

    def __init__(self) -> None:
        self.active: dict[str, list[WebSocket]] = {}

    async def connect(self, user_id: str, ws: WebSocket) -> None:
        await ws.accept()
        self.active.setdefault(user_id, []).append(ws)

    def disconnect(self, user_id: str, ws: WebSocket) -> None:
        conns = self.active.get(user_id)
        if conns and ws in conns:
            conns.remove(ws)
            if not conns:
                self.active.pop(user_id, None)

    def is_online(self, user_id: str) -> bool:
        return bool(self.active.get(user_id))

    async def send_to_users(self, user_ids: list[str], payload: dict) -> None:
        for uid in user_ids:
            for ws in list(self.active.get(uid, [])):
                try:
                    await ws.send_json(payload)
                except Exception:
                    pass


manager = ConnectionManager()
