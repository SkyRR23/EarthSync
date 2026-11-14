"""Real local HTTP smoke workflow, using an explicitly synthetic image only."""

import hashlib
import io
import json
import os

import httpx
from PIL import Image


def main():
    token = os.environ["EARTHSYNC_EVIDENCE_TOKEN"]
    data = io.BytesIO()
    Image.new("RGB", (16, 12), "green").save(data, format="PNG")
    metadata = {
        "schema_version": "evidence.v1",
        "source": "browser_file",
        "data_kind": "synthetic",
        "category": "crop",
        "caption": "SYNTHETIC upload/viewer test — not a real field photo",
        "farmer_observations": "Synthetic test only; no field condition inferred",
    }
    with httpx.Client(
        base_url="http://127.0.0.1:8017",
        timeout=30,
        headers={"Authorization": f"Bearer {token}"},
        trust_env=False,
    ) as client:
        response = client.post(
            "/api/evidence/v1/photos",
            content=data.getvalue(),
            headers={
                "Content-Type": "image/png",
                "X-EarthSync-Metadata": json.dumps(metadata, ensure_ascii=True),
            },
        )
        response.raise_for_status()
        photo = response.json()
        path = f"/api/evidence/v1/photos/{photo['id']}"
        try:
            image = client.get(path + "/image")
            image.raise_for_status()
            assert hashlib.sha256(image.content).hexdigest() == photo["sha256"]
            with Image.open(io.BytesIO(image.content)) as decoded:
                assert decoded.size == (16, 12) and not decoded.getexif()
            timeline = client.post(
                "/api/evidence/v1/timeline",
                json={
                    "field": {
                        "farm_id": "synthetic-confirmation-for-test-only",
                        "confirmed_by_farmer": True,
                        "point": {"latitude": -33.9, "longitude": 151.2},
                    },
                    "start": "2026-11-01",
                    "end": "2026-11-14",
                },
            )
            timeline.raise_for_status()
            assert timeline.json()["events"] == []  # unlocated image does not match
            assert all(
                p["status"] == "unavailable" for p in timeline.json()["providers"]
            )
        finally:
            client.delete(path).raise_for_status()
        assert client.get(path).status_code == 404
    print(
        "PASS: actual local HTTP synthetic upload, sanitized viewer, unavailable timeline, deletion"
    )


if __name__ == "__main__":
    main()
