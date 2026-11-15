"""Synthetic research client. Read a private credential file; never print its token."""

import argparse
import io
import json
from pathlib import Path
from urllib.parse import urlsplit

import httpx
from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8031")
    parser.add_argument("--credential-file", type=Path, required=True)
    args = parser.parse_args()
    parsed = urlsplit(args.base_url)
    if (
        (
            parsed.scheme != "https"
            and not (
                parsed.scheme == "http"
                and parsed.hostname in ("127.0.0.1", "localhost", "::1")
            )
        )
        or parsed.username
        or parsed.query
        or parsed.fragment
    ):
        parser.error("Use HTTPS or loopback HTTP; never put a credential in the URL")
    credential = json.loads(args.credential_file.read_text(encoding="utf-8"))
    prefix = args.base_url.rstrip("/") + "/api/research/v1"
    pixels = io.BytesIO()
    Image.new("RGB", (32, 32), "brown").save(pixels, format="PNG")
    # HTTPX verifies TLS and does not follow redirects carrying credentials.
    with httpx.Client(
        headers={"Authorization": "Bearer " + credential["token"]},
        timeout=30,
        follow_redirects=False,
    ) as client:
        evidence = client.post(
            prefix + "/crops/evidence", json={"crop": "rice", "question": "soil pH"}
        )
        evidence.raise_for_status()
        assert evidence.json()["recommendation_eligible"] is False
        photo = client.post(
            prefix + "/photos",
            params={"farm_id": credential["farm_ids"][0]},
            content=pixels.getvalue(),
            headers={"Content-Type": "image/png"},
        )
        photo.raise_for_status()
        result = client.post(
            prefix + f"/photos/{photo.json()['id']}/analyze",
            json={"farm_id": credential["farm_ids"][0]},
        )
        result.raise_for_status()
        assert result.json()["chemical_measurements_available"] is False
        deleted = client.delete(
            prefix + f"/photos/{photo.json()['id']}",
            params={"farm_id": credential["farm_ids"][0]},
        )
        deleted.raise_for_status()
        print(
            json.dumps(
                {
                    "crop_evidence": evidence.json()["status"],
                    "photo_analysis": result.json()["status"],
                    "synthetic_photo_deleted": deleted.status_code == 204,
                    "recommendation_eligible": False,
                }
            )
        )


if __name__ == "__main__":
    main()
