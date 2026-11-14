"""Fixed-source bounded HTTP transport, no caller-supplied URLs or redirects."""

import asyncio
import hashlib
import json
from dataclasses import dataclass
from datetime import datetime, timezone

import httpx

from ..errors import PlatformError

ALLOWED = {
    "https://power.larc.nasa.gov/api/temporal/daily/point",
    "https://cmr.earthdata.nasa.gov/search/granules.umm_json",
    "https://maps.isric.org/mapserv",
}


@dataclass(frozen=True)
class Capture:
    body: bytes
    retrieved_at: datetime
    headers: dict

    @property
    def sha256(self):
        return hashlib.sha256(self.body).hexdigest()

    def json(self):
        try:

            def unique(pairs):
                result = {}
                for key, value in pairs:
                    if key in result:
                        raise ValueError("Duplicate provider JSON key")
                    result[key] = value
                return result

            def reject_constant(value):
                raise ValueError("Nonfinite JSON number")

            value = json.loads(
                self.body, object_pairs_hook=unique, parse_constant=reject_constant
            )
            if not isinstance(value, dict):
                raise ValueError
            return value
        except (ValueError, UnicodeError, RecursionError) as exc:
            raise PlatformError("SCHEMA_MISMATCH", 502) from exc


class Transport:
    def __init__(self, client, concurrency=3, max_bytes=4_000_000):
        self.client = client
        self.slots = asyncio.Semaphore(concurrency)
        self.max_bytes = max_bytes

    async def get(self, url, params):
        if url not in ALLOWED:
            raise PlatformError("UNSUPPORTED_PRODUCT")
        try:
            async with asyncio.timeout(35):
                async with self.slots:
                    async with self.client.stream(
                        "GET", url, params=params, follow_redirects=False
                    ) as response:
                        if response.status_code == 429:
                            raise PlatformError("RATE_LIMIT", 429, True)
                        if response.status_code in (401, 403):
                            raise PlatformError("PROVIDER_ACCESS_DENIED", 503)
                        if response.status_code != 200:
                            raise PlatformError(
                                "PROVIDER_UNAVAILABLE", 503, response.status_code >= 500
                            )
                        data = bytearray()
                        async for part in response.aiter_bytes():
                            if len(data) + len(part) > self.max_bytes:
                                raise PlatformError("PROVIDER_RESPONSE_TOO_LARGE", 502)
                            data.extend(part)
                        return Capture(
                            bytes(data),
                            datetime.now(timezone.utc),
                            {
                                key: response.headers[key]
                                for key in ("content-type", "etag", "last-modified")
                                if key in response.headers
                            },
                        )
        except (httpx.TimeoutException, TimeoutError) as exc:
            raise PlatformError("TIMEOUT", 504, True) from exc
        except httpx.ProxyError as exc:
            raise PlatformError("OUTBOUND_PROXY_BLOCKED", 503) from exc
        except httpx.TransportError as exc:
            raise PlatformError("PROVIDER_UNAVAILABLE", 503, True) from exc
