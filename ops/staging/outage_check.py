"""Controlled provider failure, using the real API/transport and a fresh test DB.

The injected HTTP 503 is fault injection, never a live provider success receipt.
"""

import asyncio
from pathlib import Path
import tempfile


def exercise():
    import httpx
    from fastapi.testclient import TestClient
    from earthsync.platform_v1.api import create_app, PREFIX
    from earthsync.platform_v1.providers.transport import Transport
    from earthsync.platform_v1.store import Store

    with tempfile.TemporaryDirectory(prefix="earthsync-7q-outage-") as directory:
        store = Store(Path(directory).resolve() / "data")
        upstream = httpx.AsyncClient(
            transport=httpx.MockTransport(
                lambda request: httpx.Response(
                    503, text="INJECTED_PRIVATE_PROVIDER_MESSAGE"
                )
            )
        )
        try:
            app = create_app(
                store=store, local_enabled=True, transport=Transport(upstream)
            )
            with TestClient(
                app, base_url="http://127.0.0.1", client=("127.0.0.1", 10000)
            ) as client:
                response = client.post(
                    PREFIX + "/climate/jobs",
                    json={
                        "query": {
                            "point": {"latitude": 42.03, "longitude": -93.62},
                            "start": "2024-02-01",
                            "end": "2024-02-29",
                        }
                    },
                )
                assert response.status_code == 202
                initial = response.json()

                async def join():
                    await app.state.jobs.queue.join()

                client.portal.call(join)
                response = client.get(PREFIX + "/jobs/" + initial["id"])
                value = response.json()
                # A completed retrieval job may legitimately contain only gaps.
                # Its terminal status alone must never be called live-data success.
                assert value["status"] == "succeeded"
                assert value["result"]["records"] == []
                assert len(value["result"]["gaps"]) == 3
                assert all(
                    g["code"] == "PROVIDER_UNAVAILABLE" and g["retryable"]
                    for g in value["result"]["gaps"]
                )
                assert "INJECTED_PRIVATE_PROVIDER_MESSAGE" not in response.text
                with store.connection() as db:
                    assert (
                        db.execute("SELECT count(*) FROM evidence").fetchone()[0] == 0
                    )
                    assert (
                        db.execute("SELECT count(*) FROM source_cache").fetchone()[0]
                        == 0
                    )
        finally:
            asyncio.run(upstream.aclose())
    return "Injected HTTP 503 produces 3 explicit retryable gaps, zero evidence/cache entries and no synthetic fallback or raw provider body"
