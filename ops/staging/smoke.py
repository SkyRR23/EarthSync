"""Loopback HTTP staging smoke. Mutates ONLY an explicitly disposable instance.

Reports PASS/FAIL/BLOCKED; exit 0=pass, 1=fail, 2=incomplete. No live fallback.
Use exercise, stop/restart the same instance, then restart with the saved receipt.
"""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import time
from urllib.parse import urlsplit

import httpx

from report import Report


def local_url(value):
    parsed = urlsplit(value)
    if (
        parsed.scheme != "http"
        or parsed.hostname != "127.0.0.1"
        or parsed.username
        or parsed.password
        or parsed.path not in ("", "/")
        or parsed.query
        or parsed.fragment
    ):
        raise argparse.ArgumentTypeError("Use a literal http://127.0.0.1:PORT origin")
    return value.rstrip("/")


def checked(response, status=200):
    assert response.status_code == status
    assert "application/json" in response.headers.get("content-type", "")
    return response.json()


def platform(client, args, report, receipt):
    prefix = "/api/platform/v1"

    try:
        import earthsync.platform_v1  # noqa: F401
    except ImportError:
        report.add(
            "controlled provider outage",
            "BLOCKED",
            "Set PYTHONPATH to the verified platform runtime for isolated fault injection",
        )
    else:
        from outage_check import exercise

        report.check("controlled provider outage", exercise)

    def readiness():
        value = checked(client.get(prefix + "/ready"))
        assert (
            value["ready"]
            and value["storage"]
            and value["rust_v03_startup_probe_passed"]
        )
        assert value["hosted_private_api_enabled"] is False
        return "Storage integrity and actual Rust startup probe passed; hosted access disabled"

    if not report.check("platform readiness", readiness):
        return

    def boundary():
        assert (
            client.get(
                prefix + "/farms", headers={"Host": "external.invalid"}
            ).status_code
            == 403
        )
        assert (
            client.get(
                prefix + "/farms", headers={"Origin": "https://external.invalid"}
            ).status_code
            == 403
        )
        value = checked(
            client.post(prefix + "/farms", json={"confirmed_point": {"latitude": 999}}),
            422,
        )
        assert value["error"]["code"] == "INVALID_INPUT"
        assert (
            checked(client.get(prefix + "/farms/not-a-uuid"), 422)["error"]["code"]
            == "INVALID_INPUT"
        )
        return (
            "External Host/Origin denied and malformed requests rejected with safe JSON"
        )

    report.check("private boundary and invalid requests", boundary)
    if args.phase == "restart":

        def persisted():
            assert receipt["platform_state"] == str(args.platform_state.resolve())
            lock = args.platform_state / "operation.lock"
            generation = [int((lock / "pid").read_text()), lock.stat().st_mtime_ns]
            assert generation != receipt["generation"], (
                "Stop/restart the service before checking persistence"
            )
            farm = checked(client.get(prefix + "/farms/" + receipt["farm"]))
            assert farm["id"] == receipt["farm"]
            decisions = checked(client.get(prefix + f"/farms/{farm['id']}/decisions"))
            assert any(d["id"] == receipt["decision"] for d in decisions)
            for ident, digest in receipt.get("evidence", {}).items():
                value = checked(client.get(prefix + "/evidence/" + ident))
                assert (
                    value["response_sha256"] == digest
                    and value["data_type"] != "synthetic"
                )
            if receipt.get("job"):
                assert (
                    checked(client.get(prefix + "/jobs/" + receipt["job"]))["status"]
                    == "succeeded"
                )
            response = client.get(
                prefix + f"/farms/{farm['id']}/photos/{receipt['photo']}/image"
            )
            assert response.status_code == 200
            assert (
                hashlib.sha256(response.content).hexdigest() == receipt["photo_sha256"]
            )
            fields = ["farm", "decision", "private photo"]
            if receipt.get("evidence"):
                fields.append("evidence lineage")
            if receipt.get("job"):
                fields.append("terminal job")
            return (
                ", ".join(fields) + " survive a verified change of service generation"
            )

        report.check("database persistence after restart", persisted)
        return

    farm = checked(
        client.post(
            prefix + "/farms",
            json={
                "name": "DISPOSABLE OPS SMOKE; no field ground truth",
                "confirmed_point": {"latitude": 42.03, "longitude": -93.62},
                "confirmed_on": "2026-11-14",
                "production_system": "rainfed",
            },
        ),
        201,
    )
    receipt["farm"] = farm["id"]
    lock = args.platform_state / "operation.lock"
    receipt["platform_state"] = str(args.platform_state.resolve())
    receipt["generation"] = [int((lock / "pid").read_text()), lock.stat().st_mtime_ns]
    assert checked(client.get(prefix + "/farms/" + farm["id"])) == farm
    report.add(
        "farm create and retrieve", "PASS", "Confirmed sample farm stored and retrieved"
    )
    evidence = []
    if args.live:

        def nasa():
            submission = checked(
                client.post(
                    prefix + "/climate/jobs",
                    json={
                        "farm_id": farm["id"],
                        "query": {
                            "point": farm["confirmed_point"],
                            "start": "2024-02-01",
                            "end": "2024-02-29",
                        },
                    },
                ),
                202,
            )
            assert submission["status"] in ("queued", "running", "succeeded")
            seen = [submission["status"]]
            deadline = time.monotonic() + 125
            while time.monotonic() < deadline:
                job = checked(client.get(prefix + "/jobs/" + submission["id"]))
                seen.append(job["status"])
                if job["status"] in ("succeeded", "failed", "cancelled"):
                    break
                time.sleep(0.75)
            assert job["status"] == "succeeded" and not job["result"]["gaps"]
            assert job["result"]["cache_hit"] is False, (
                "Use a fresh disposable service for live proof"
            )
            records = job["result"]["records"]
            assert len(records) == 3
            context = checked(client.get(prefix + f"/farms/{farm['id']}/context"))
            assert {r["id"] for r in context["evidence"]} == {r["id"] for r in records}
            for record in records:
                assert record["provider"] == "NASA POWER"
                assert (
                    record["data_type"] == "modeled" and "MERRA-2" in record["dataset"]
                )
                assert record["source_url"].startswith("https://power.larc.nasa.gov/")
                assert len(record["response_sha256"]) == 64
                assert len(record["measurements"]) == 29 and record["source_metadata"]
                assert record["temporal"]["start"] == "2024-02-01"
                assert record["spatial"]["query_point"] == farm["confirmed_point"]
                assert (
                    checked(client.get(prefix + "/evidence/" + record["id"])) == record
                )
            evidence.extend(records)
            receipt["evidence"] = {r["id"]: r["response_sha256"] for r in records}
            receipt["job"] = submission["id"]
            return (
                "Live uncached historical POWER: 3 original hashes/lineage records, 29 days, correct farm; states "
                + " → ".join(dict.fromkeys(seen))
            )

        report.check("live NASA provenance and job transitions", nasa)
    else:
        report.add(
            "live NASA provenance and job transitions",
            "BLOCKED",
            "Run --live on a fresh disposable service; captured fixtures cannot satisfy this check",
        )

    def assessment():
        value = checked(
            client.post(
                prefix + "/assessments",
                json={
                    "farm_id": farm["id"],
                    "evidence_ids": [r["id"] for r in evidence],
                    "profile_ids": ["us_ia_story_corn_rainfed_v1"],
                    "pilot_id": "us_ia_story",
                    "start": "2024-02-01",
                    "end": "2024-02-29",
                },
            )
        )
        assert (
            value["result"]["status"] == "success"
            and value["recommendation_eligible"] is False
        )
        data = value["result"]["data"]
        assert data["schema_version"] == "earthsync.engine.v0.3.0"
        assert (
            data["software_test_only"] is False
            and data["context"]["farm"]["field_id"] == farm["id"]
        )
        assert data["summaries"] and all(
            s["status"] == "insufficient_information" for s in data["summaries"]
        )
        decisions = checked(client.get(prefix + f"/farms/{farm['id']}/decisions"))
        assert len(decisions) == 1
        receipt["decision"] = decisions[0]["id"]
        catalog = checked(client.get(prefix + "/catalog/us_ia_story_corn_rainfed_v1"))
        assert catalog["recommendation_eligible"] is False
        return "Compiled Rust v0.3, farm association, persisted decision and reference-only crop status"

    report.check("actual Rust and decision history", assessment)

    def photos():
        from PIL import Image

        raw = io.BytesIO()
        Image.new("RGB", (4, 4), "green").save(raw, "PNG")
        photo = checked(
            client.post(
                prefix + f"/farms/{farm['id']}/photos",
                content=raw.getvalue(),
                headers={"Content-Type": "image/png"},
            ),
            201,
        )
        response = client.get(
            prefix + f"/farms/{farm['id']}/photos/{photo['id']}/image"
        )
        assert (
            response.status_code == 200
            and response.headers["cache-control"] == "no-store"
        )
        assert hashlib.sha256(response.content).hexdigest() == photo["sha256"]
        receipt.update(photo=photo["id"], photo_sha256=photo["sha256"])
        report.add(
            "photo authorization model",
            "PASS",
            "7I local OS principal only; no hosted user authentication is implied",
        )
        return (
            "Sanitized image stored privately and retrieved with matching hash/no-store"
        )

    report.check("platform private photos", photos)
    receipt["assistant_context"] = checked(
        client.get(prefix + f"/farms/{farm['id']}/assistant-context")
    )
    report.add(
        "database persistence after restart",
        "BLOCKED",
        "Stop and restart this service, then run --phase restart with this receipt",
    )


def web(client, args, report, receipt):
    def frontend():
        response = client.get("/")
        assert response.status_code == 200 and "flutter_bootstrap.js" in response.text
        for asset in ("/flutter_bootstrap.js", "/main.dart.js"):
            assert client.get(asset).status_code == 200
        checked(client.get("/api/v1/health"))
        assert client.get("/api/unknown-ops-route").status_code == 404
        return "Flutter HTML/bootstrap/main bundle and API JSON load; unknown API is not static HTML"

    report.check("frontend and API HTTP", frontend)

    def photos():
        # No secret values in argv, reports or error messages.
        token = args.token_file.read_text().strip() if args.token_file else None
        response = client.get("/api/evidence/v1/photos")
        assert response.status_code in (401, 403)
        if token:
            checked(
                client.get(
                    "/api/evidence/v1/photos",
                    headers={"Authorization": "Bearer " + token},
                )
            )
        else:
            raise ValueError(
                "Supply --token-file for authorized workspace verification"
            )
        return "Unauthenticated requests rejected; private token accepted locally"

    report.check("web workspace photo authorization", photos)

    context = receipt.get("assistant_context")
    if context:

        def assistant():
            value = checked(
                client.post(
                    "/api/assistant/v1/chat",
                    json={
                        "question": "What rainfall evidence is available?",
                        "context": context,
                    },
                )
            )
            assert value["context_id"] == context["context_id"] and value["claims"]
            assert all(not e.get("synthetic", False) for e in value["evidence"])
            assert {x["id"] for x in value["citations"]} <= {
                x["id"] for x in context["sources"]
            }
            return "Actual deterministic assistant runs against stored platform source context"

        report.check("assistant API", assistant)
    else:
        report.add(
            "assistant API",
            "BLOCKED",
            "Exercise the platform first to obtain stored source context",
        )
    report.add(
        "complete Flutter UI and outage recovery",
        "BLOCKED",
        "Run candidate-specific browser acceptance; HTTP cannot establish complete rendered UI behavior",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", choices=["web", "platform", "full"], default="full")
    parser.add_argument("--web-url", type=local_url, default="http://127.0.0.1:8080")
    parser.add_argument(
        "--platform-url", type=local_url, default="http://127.0.0.1:8021"
    )
    parser.add_argument(
        "--disposable",
        action="store_true",
        required=True,
        help="Affirm both services use dedicated TEST state, never real user data",
    )
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--phase", choices=["exercise", "restart"], default="exercise")
    parser.add_argument("--token-file", type=Path)
    parser.add_argument(
        "--platform-state",
        type=Path,
        help="Disposable staging.py platform state, required for restart-generation proof",
    )
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.scope in ("platform", "full") and not args.platform_state:
        parser.error(
            "Platform smoke requires --platform-state for explicit restart proof"
        )
    if args.phase == "exercise" and args.receipt.exists():
        parser.error("Exercise receipt must be new; do not overwrite previous proof")
    receipt = json.loads(args.receipt.read_text()) if args.phase == "restart" else {}
    report = Report()
    if args.scope in ("platform", "full"):
        with httpx.Client(
            base_url=args.platform_url, timeout=35, trust_env=False
        ) as client:
            report.check(
                "platform HTTP flow", lambda: platform(client, args, report, receipt)
            )
    if args.scope in ("web", "full"):
        with httpx.Client(base_url=args.web_url, timeout=35, trust_env=False) as client:
            report.check("web HTTP flow", lambda: web(client, args, report, receipt))
    if args.phase == "exercise":
        with args.receipt.open("x") as stream:
            args.receipt.chmod(0o600)
            json.dump(receipt, stream, indent=2)
    return report.write(args.report)


if __name__ == "__main__":
    if os.name != "nt":
        os.umask(0o077)
    raise SystemExit(main())
