"""Availability is independent of scientific usability and service liveness."""

from datetime import datetime, timedelta, timezone


def forecast_freshness(retrieved, issued, valid_start, valid_end, now=None):
    now = now or datetime.now(timezone.utc)
    values = [retrieved, valid_start, valid_end, now] + ([issued] if issued else [])
    if any(v.tzinfo is None or v.utcoffset() is None for v in values):
        return "invalid"
    if (
        retrieved > now
        or valid_end <= valid_start
        or (issued and issued > min(retrieved, valid_start))
    ):
        return "invalid"
    if now >= min(retrieved + timedelta(hours=1), valid_end):
        return "stale"
    if issued is None:
        return "issue_time_unknown"
    if now - issued >= timedelta(hours=12):
        return "stale"
    return "fresh"


class SourceHealth:
    def __init__(self):
        self.results = {}

    def record(self, provider, code, retryable=False):
        self.results[provider] = {
            "provider": provider,
            "state": "reachable" if code == "OK" else "unavailable",
            "code": code,
            "retryable": retryable,
            "checked_at": datetime.now(timezone.utc).isoformat(),
        }

    def snapshot(self):
        return {
            "sources": list(self.results.values()),
            "limitation": "Last attempted transport/contract check; reachability does not certify scientific usability. No probes are run by health requests.",
        }
