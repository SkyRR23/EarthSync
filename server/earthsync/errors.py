"""Stable HTTP errors: safe messages only, never raw provider/process details."""

from fastapi.responses import JSONResponse


class ServiceError(Exception):
    def __init__(self, code, message, status_code=502, retryable=False):
        super().__init__(code)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.retryable = retryable


def error_response(code, message, status_code, retryable=False):
    return JSONResponse(
        status_code=status_code,
        content={
            "status": "error",
            "error": {"code": code, "message": message, "retryable": retryable},
        },
        headers={"Cache-Control": "no-store"},
    )
