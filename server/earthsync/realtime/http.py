"""Bounded, conditional HTTP with persisted validators and provider throttling."""

import asyncio
import hashlib
import json
import re
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from urllib.parse import urlsplit

import httpx

USER_AGENT = "EarthSync/1.0 (https://github.com/SkyRR23/EarthSync)"
HOSTS = {
    "mesonet.agron.iastate.edu",
    "api.weather.gov",
    "api.open-meteo.com",
    "cmr.earthdata.nasa.gov",
}
MAX_BYTES = 2_000_000


class SourceError(Exception):
    def __init__(self, code, *, retry_after=0, details=None):
        self.code, self.retry_after = code, retry_after
        self.details = details
        super().__init__(code)


def retry_seconds(value, now):
    try:
        return max(0, float(value))
    except (ValueError, TypeError):
        try:
            return max(0, parsedate_to_datetime(value).timestamp() - now)
        except (ValueError, TypeError, OverflowError):
            return 0


class CachedHttp:
    def __init__(self, client, repository, clock=time.time):
        self.client, self.repository, self.clock = client, repository, clock
        self.locks = {host: asyncio.Lock() for host in HOSTS}
        previous = {host: repository.get("backoff:" + host) or {} for host in HOSTS}
        self.blocked_until = {
            host: state.get("until", 0) for host, state in previous.items()
        }
        self.delays = {host: state.get("delay", 0) for host, state in previous.items()}

    async def get(self, url, *, ttl):
        parsed = urlsplit(url)
        if parsed.scheme != "https" or parsed.hostname not in HOSTS or parsed.username:
            raise SourceError("UNSUPPORTED_ENDPOINT")
        host = parsed.hostname
        key = "http:" + hashlib.sha256(url.encode()).hexdigest()
        async with self.locks[host]:
            now = self.clock()
            old = self.repository.get(key)
            if old and old["next_check"] > now:
                return old
            if self.blocked_until.get(host, 0) > now:
                raise SourceError(
                    "PROVIDER_BACKOFF", retry_after=self.blocked_until[host] - now
                )
            headers = {
                "User-Agent": USER_AGENT,
                "Accept": "application/geo+json, application/json, text/plain",
            }
            if old:
                if old.get("etag"):
                    headers["If-None-Match"] = old["etag"]
                if old.get("last_modified"):
                    headers["If-Modified-Since"] = old["last_modified"]
            started = time.perf_counter()
            try:
                async with self.client.stream(
                    "GET", url, headers=headers, follow_redirects=False
                ) as response:
                    status = response.status_code
                    if status not in (200, 304):
                        code = {
                            401: "AUTHENTICATION_REQUIRED",
                            403: "AUTHORIZATION_DENIED",
                            404: "UNSUPPORTED_ENDPOINT",
                            429: "RATE_LIMIT",
                        }.get(
                            status, "PROVIDER_OUTAGE" if status >= 500 else "HTTP_ERROR"
                        )
                        raise SourceError(
                            code,
                            retry_after=retry_seconds(
                                response.headers.get("retry-after"), now
                            ),
                        )
                    if status == 304 and not old:
                        raise SourceError("INVALID_DATA")
                    raw = bytearray()
                    if status == 200:
                        async for chunk in response.aiter_bytes():
                            raw.extend(chunk)
                            if len(raw) > MAX_BYTES:
                                raise SourceError("RESPONSE_TOO_LARGE")
                        if not raw:
                            raise SourceError("EMPTY_RESPONSE")
                    cache_control = response.headers.get("cache-control", "")
                    max_age = re.search(r"(?:^|,)\s*max-age=(\d+)", cache_control)
                    # Provider lifetime is a minimum; browser requests cannot shorten it.
                    delay = max(
                        ttl,
                        max(0, int(max_age[1]) - int(response.headers.get("age", "0")))
                        if max_age
                        else ttl,
                    )
                    result = {
                        "url": url,
                        "text": raw.decode("utf-8") if status == 200 else old["text"],
                        "sha256": hashlib.sha256(raw).hexdigest()
                        if status == 200
                        else old["sha256"],
                        "etag": response.headers.get(
                            "etag", old.get("etag") if old else None
                        ),
                        "last_modified": response.headers.get(
                            "last-modified", old.get("last_modified") if old else None
                        ),
                        "retrieved_at": datetime.fromtimestamp(
                            self.clock(), timezone.utc
                        ).isoformat(),
                        "next_check": now + delay,
                        "http_status": status,
                        "request_ms": round((time.perf_counter() - started) * 1000, 2),
                    }
                    if "no-store" not in cache_control:
                        self.repository.put(key, result)
                    self.delays[host] = 0
                    return result
            except (SourceError, httpx.HTTPError, UnicodeError, ValueError) as exc:
                if isinstance(exc, SourceError):
                    error = exc
                elif isinstance(exc, httpx.ProxyError):
                    error = SourceError("NETWORK_POLICY_OR_PROXY")
                elif isinstance(exc, httpx.TimeoutException):
                    error = SourceError("PROVIDER_TIMEOUT")
                else:
                    error = SourceError(
                        "NETWORK_OR_TLS_ERROR"
                        if isinstance(exc, httpx.HTTPError)
                        else "INVALID_DATA"
                    )
                delay = min(1800, max(60, self.delays.get(host, 0) * 2))
                self.delays[host] = delay
                self.blocked_until[host] = now + max(delay, error.retry_after)
                self.repository.put(
                    "backoff:" + host,
                    {"until": self.blocked_until[host], "delay": delay},
                )
                raise error from exc

    async def json(self, url, *, ttl):
        receipt = await self.get(url, ttl=ttl)
        try:

            def unique(pairs):
                value = {}
                for key, item in pairs:
                    if key in value:
                        raise ValueError("Duplicate JSON key")
                    value[key] = item
                return value

            def reject_constant(value):
                raise ValueError("Nonfinite JSON constant")

            value = json.loads(
                receipt["text"],
                object_pairs_hook=unique,
                parse_constant=reject_constant,
            )
            if not isinstance(value, dict):
                raise ValueError("Expected object")
            return value, receipt
        except (ValueError, TypeError) as exc:
            raise SourceError("INVALID_DATA") from exc
