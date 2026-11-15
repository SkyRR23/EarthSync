"""Transparent ASGI limits without changing the legacy subprocess task context."""

from starlette.responses import JSONResponse


class DemoApiMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        path = scope["path"]
        downstream_receive = receive
        if path.startswith(
            (
                "/api/assistant/",
                "/api/environmental/",
                "/api/catalog/",
                "/api/satellite/",
            )
        ):
            body = bytearray()
            while True:
                message = await receive()
                if message["type"] == "http.disconnect":
                    return
                chunk = message.get("body", b"")
                if len(body) + len(chunk) > 2_000_000:
                    response = JSONResponse(
                        status_code=413,
                        content={
                            "error": {"code": "REQUEST_TOO_LARGE", "retryable": False}
                        },
                        headers={"Cache-Control": "no-store"},
                    )
                    return await response(scope, receive, send)
                body.extend(chunk)
                if not message.get("more_body", False):
                    break
            replayed = False

            async def replay():
                nonlocal replayed
                if not replayed:
                    replayed = True
                    return {
                        "type": "http.request",
                        "body": bytes(body),
                        "more_body": False,
                    }
                return await receive()

            downstream_receive = replay

        async def private_send(message):
            if message["type"] == "http.response.start" and path.startswith("/api/"):
                message = {
                    **message,
                    "headers": [
                        (key, value)
                        for key, value in message.get("headers", [])
                        if key.lower() != b"cache-control"
                    ]
                    + [(b"cache-control", b"no-store")],
                }
            await send(message)

        return await self.app(scope, downstream_receive, private_send)
