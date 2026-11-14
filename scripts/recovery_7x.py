"""Offline rehearsal for disposable 7X stores; originals are never overwritten.

All output contains row counts and hashes, never tokens, photo bytes or row data.
Stop both services first. Private paths must be outside this source checkout.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import socket
import sqlite3
import subprocess
import sys

import httpx

ROOT = Path(__file__).resolve().parents[1]


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def database(path):
    with sqlite3.connect(path.as_uri() + "?mode=ro", uri=True) as connection:
        assert connection.execute("PRAGMA integrity_check").fetchone() == ("ok",)
        tables = connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        ).fetchall()
        result = {}
        for (table,) in tables:
            quoted = '"' + table.replace('"', '""') + '"'
            rows = connection.execute("SELECT * FROM " + quoted).fetchall()
            encoded = sorted(
                json.dumps(
                    row,
                    default=lambda value: {"blob_sha256": digest(value)},
                    sort_keys=True,
                    separators=(",", ":"),
                )
                for row in rows
            )
            result[table] = {
                "rows": len(rows),
                "sha256": digest("\n".join(encoded).encode()),
            }
        return result


def fingerprint(platform, workspace):
    return {
        "platform": database(platform / "platform.sqlite3"),
        "workspace": database(workspace / "evidence.sqlite3"),
        "workspace_token_sha256": digest(
            (workspace / "workspace-token.txt").read_bytes()
        ),
        "platform_objects": {
            str(p.relative_to(platform)): digest(p.read_bytes())
            for p in sorted((platform / "objects").rglob("*"))
            if p.is_file()
        },
    }


def stopped():
    for port in [8021, 8091]:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                raise RuntimeError(
                    "Stop both acceptance services before offline maintenance"
                )
        except (ConnectionRefusedError, TimeoutError):
            pass


def verify_http(workspace, evidence, output):
    assert not output.exists(), "Preserve prior receipts"
    with httpx.Client(trust_env=False, timeout=20) as client:
        base = "http://127.0.0.1:8021/api/platform/v1"

        def get(path):
            response = client.get(base + path)
            assert response.status_code == 200
            return response.json()

        assert get("/ready")["ready"] is True
        job = json.loads((evidence / "browser-7w/live-water-job.json").read_text())
        assert get("/jobs/" + job["id"]) == job
        for record in job["result"]["records"]:
            assert get("/evidence/" + record["id"]) == record
        farm = json.loads((evidence / "browser-7w/farm-confirmation.json").read_text())[
            "farm"
        ]
        decisions = {
            d["id"]: d["assessment"] for d in get("/farms/" + farm["id"] + "/decisions")
        }
        for name in ["saved-rust-v2-assessment", "alternative-A", "alternative-B"]:
            saved = json.loads((evidence / "browser-7w" / (name + ".json")).read_text())
            ident = saved.pop("decision_id")
            assert decisions[ident] == saved
        photos = json.loads((evidence / "recovery-photo-fixtures.json").read_text())
        response = client.get(
            base
            + f"/farms/{photos['platform_farm']}/photos/{photos['platform_photo']}/image"
        )
        assert (
            response.status_code == 200
            and digest(response.content) == photos["image_sha256"]
        )
        token = (workspace / "workspace-token.txt").read_text().strip()
        response = client.get(
            "http://127.0.0.1:8091/api/evidence/v1/photos/"
            + photos["workspace_photo"]
            + "/image",
            headers={"Authorization": "Bearer " + token},
        )
        assert (
            response.status_code == 200
            and digest(response.content) == photos["image_sha256"]
        )
        for headers in [
            {"Origin": "https://untrusted.example"},
            {"Host": "untrusted.example"},
        ]:
            assert client.get(base + "/farms", headers=headers).status_code == 403
        output.write_text(
            json.dumps(
                {
                    "status": "PASS",
                    "ready": True,
                    "exact_original_job": True,
                    "exact_evidence_records": len(job["result"]["records"]),
                    "exact_assessments": 3,
                    "separate_photos_verified": 2,
                    "host_origin_protection": True,
                },
                indent=2,
            )
            + "\n"
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command", choices=["snapshot", "backup-restore", "verify", "verify-http"]
    )
    parser.add_argument("--private", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--restored", action="store_true")
    parser.add_argument("--browser-evidence", type=Path)
    args = parser.parse_args()
    private = args.private.absolute()
    assert (
        private.resolve() == private
        and private != ROOT
        and ROOT not in private.parents
        and private not in ROOT.parents
    )
    platform = private / ("platform-restored" if args.restored else "platform")
    workspace = private / ("workspace-restored" if args.restored else "workspace")
    if args.command == "verify-http":
        assert args.browser_evidence is not None
        verify_http(workspace, args.browser_evidence, args.receipt)
        print(
            "PASS: restarted HTTP services retain exact NASA lineage, Rust assessments and both protected photos"
        )
        return
    stopped()
    current = fingerprint(platform, workspace)
    if args.command == "snapshot":
        assert not args.receipt.exists(), "Preserve prior receipts"
        args.receipt.write_text(json.dumps(current, indent=2) + "\n")
    elif args.command == "verify":
        assert current == json.loads(args.receipt.read_text()), (
            "Stored rows/objects/token changed"
        )
    else:
        assert not args.restored
        assert current == json.loads(args.receipt.read_text())
        for command, directory in [
            ("backup", platform),
            ("restore", private / "platform-restored"),
        ]:
            subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "earthsync.platform_v1.maintenance",
                    command,
                    "--directory",
                    str(directory),
                    "--backup",
                    str(private / "platform-backup"),
                ],
                check=True,
            )
        backup = private / "workspace-backup"
        backup.mkdir(mode=0o700)
        restored = private / "workspace-restored"
        restored.mkdir(mode=0o700)
        for target in [backup, restored]:
            with sqlite3.connect(workspace / "evidence.sqlite3") as source:
                with sqlite3.connect(target / "evidence.sqlite3") as destination:
                    source.backup(destination)
            (target / "evidence.sqlite3").chmod(0o600)
            shutil.copy2(
                workspace / "workspace-token.txt", target / "workspace-token.txt"
            )
            (target / "workspace-token.txt").chmod(0o600)
        assert fingerprint(private / "platform-restored", restored) == current
    print(
        "PASS: SQLite integrity, exact table rows, separate photo stores and private token hashes; "
        + args.command
    )


if __name__ == "__main__":
    main()
