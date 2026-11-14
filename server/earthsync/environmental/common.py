"""Bounded transport, provenance and independent per-source caches."""

import asyncio
import hashlib
import json
import math
import time
from collections import OrderedDict, deque
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Callable

import httpx

from .models import Evidence, Quality, Retrieval, SpatialSupport, TemporalSupport


def utcnow():
    return datetime.now(timezone.utc)


class SourceError(Exception):
    def __init__(self, code, retrieval=None):
        self.code, self.retrieval = code, retrieval


def number(value):
    try:
        return type(value) in (int, float) and math.isfinite(value)
    except OverflowError:
        return False


def quality(values, reasons, qa_status="not_applicable", quantiles=False):
    return Quality(
        expected=len(values),
        present=sum(v.quality == "present" for v in values),
        missing=sum(v.quality == "missing" for v in values),
        rejected=sum(v.quality == "rejected" for v in values),
        qa_status=qa_status,
        uncertainty_status="provider_quantiles" if quantiles else "not_supplied",
        reasons=reasons,
    )


def unavailable(kind, source, point, reason, retrieval=None):
    return Evidence(
        context_kind=kind,
        availability="unavailable",
        reason=reason,
        source=source.model_copy(deep=True),
        retrieval=retrieval,
        spatial_support=SpatialSupport(query_point=point, method="not_retrieved"),
        temporal_support=TemporalSupport(
            kind=(
                "static_model"
                if kind == "soil"
                else "weather"
                if kind == "weather"
                else "satellite_composite"
            )
        ),
        quality=quality(
            [], [reason], "missing" if kind not in ("soil", "weather") else "unverified"
        ),
        limitations=[
            "No usable environmental values; unknown is not a favorable condition."
        ],
    )


@dataclass(frozen=True)
class Capture:
    body: bytes
    retrieval: Retrieval

    def json(self):
        def invalid_constant(value):
            raise ValueError("Nonfinite JSON constant")

        def pairs(items):
            result = {}
            for key, value in items:
                if key in result:
                    raise ValueError("Duplicate JSON key")
                result[key] = value
            return result

        try:
            result = json.loads(
                self.body,
                object_pairs_hook=pairs,
                parse_constant=invalid_constant,
            )
            if not isinstance(result, dict):
                raise ValueError("Expected object")
            return result
        except (ValueError, UnicodeError, RecursionError) as exc:
            raise SourceError("INVALID_RESPONSE", self.retrieval) from exc


async def fetch(client, endpoint, params, now=utcnow):
    retrieval = Retrieval(requested_at=now(), endpoint=endpoint, query=params)
    try:
        async with asyncio.timeout(25):
            async with client.stream("GET", endpoint, params=params) as response:
                retrieval.http_status = response.status_code
                if response.status_code != 200:
                    raise SourceError("UPSTREAM_HTTP_ERROR", retrieval)
                content = bytearray()
                async for chunk in response.aiter_bytes():
                    content.extend(chunk)
                    if len(content) > 2_000_000:
                        raise SourceError("RESPONSE_TOO_LARGE", retrieval)
                retrieval.retrieved_at = now()
                retrieval.response_sha256 = hashlib.sha256(content).hexdigest()
                retrieval.etag = response.headers.get("etag")
                retrieval.last_modified = response.headers.get("last-modified")
                return Capture(bytes(content), retrieval)
    except (httpx.TimeoutException, TimeoutError) as exc:
        raise SourceError("UPSTREAM_TIMEOUT", retrieval) from exc
    except httpx.RequestError as exc:
        raise SourceError("UPSTREAM_TRANSPORT_UNAVAILABLE", retrieval) from exc


class SourceCache:
    """One instance per source/policy. No stale fallback or failure caching.

    Exact query keys avoid re-associating rounded locations with another farm.
    Returned copies prevent downstream mutation of cached scientific metadata.
    """

    def __init__(self, ttl, capacity=64, clock=time.monotonic):
        self.ttl, self.capacity, self.clock = ttl, capacity, clock
        self.entries = OrderedDict()
        self.lock = asyncio.Lock()

    async def get(self, key, loader: Callable, now):
        async with self.lock:
            if key in self.entries:
                deadline, evidence = self.entries[key]
                expiry = evidence.temporal_support.expires_at
                if deadline > self.clock() and (expiry is None or now() < expiry):
                    self.entries.move_to_end(key)
                    result = evidence.model_copy(deep=True)
                    result.cache_hit = True
                    return result
                del self.entries[key]
            evidence = await loader()
            # Cache only fully parsed captures. Partial values remain partial.
            if evidence.availability != "unavailable":
                self.entries[key] = (
                    self.clock() + self.ttl,
                    evidence.model_copy(deep=True),
                )
                while len(self.entries) > self.capacity:
                    self.entries.popitem(last=False)
            return evidence


class RequestBudget:
    """Per-process sliding-window attempt budget; never sleeps or retries."""

    def __init__(self, limit, window, clock=time.monotonic):
        self.limit, self.window, self.clock = limit, window, clock
        self.attempts = deque()

    def take(self):
        now = self.clock()
        while self.attempts and self.attempts[0] <= now - self.window:
            self.attempts.popleft()
        if len(self.attempts) >= self.limit:
            return False
        self.attempts.append(now)
        return True
