import json
import os
import subprocess
import sys
from pathlib import Path

from earthsync.research.api import PREFIX, create_app
from earthsync.research.storage import ResearchStore


def test_cli_one_time_secret_and_revoke(tmp_path):
    private = tmp_path / "private"
    secret_file = tmp_path / "credential.json"
    prefix = [
        sys.executable,
        "-m",
        "earthsync.research.cli",
        "--directory",
        str(private),
    ]
    provision = [
        *prefix,
        "provision",
        "--tenant",
        "synthetic",
        "--subject",
        "alice",
        "--scope",
        "crop:evidence:read",
        "--secret-file",
        str(secret_file),
    ]
    result = subprocess.run(provision, capture_output=True, text=True, check=True)
    credential = json.loads(secret_file.read_text())
    assert credential["token"] not in result.stdout + result.stderr
    if os.name != "nt":
        assert secret_file.stat().st_mode & 0o077 == 0
    assert subprocess.run(provision, capture_output=True).returncode != 0
    store = ResearchStore(private)
    assert store.authenticate(credential["token"])["id"] == credential["key_id"]
    subprocess.run(
        [*prefix, "revoke", credential["key_id"]], capture_output=True, check=True
    )
    with store.connection() as db:
        assert db.execute("SELECT revoked FROM credentials").fetchone()[0] == 1


def test_generated_openapi_matches_runtime_scopes(research_store, evidence_index):
    app = create_app(store=research_store, index=evidence_index)
    schema = app.openapi()
    assert schema["paths"][PREFIX + "/photos"]["post"]["x-required-scopes"] == [
        "photo:upload"
    ]
    assert schema["paths"][PREFIX + "/health"]["get"]["responses"]["401"]["content"][
        "application/json"
    ]["schema"]["$ref"].endswith("ResearchError")
    root = Path(__file__).resolve().parents[3]
    assert schema == json.loads(
        (root / "docs/crop-intelligence/openapi.json").read_text()
    )
