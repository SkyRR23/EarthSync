"""Sanitized errors. Never include provider URLs with credentials or payloads."""


class PlatformError(Exception):
    def __init__(self, code: str, status=422, retryable=False):
        self.code, self.status, self.retryable = code, status, retryable
        super().__init__(code)
