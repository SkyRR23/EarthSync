import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parents[1]))
from report import Report
from staging import (
    copy_research_references,
    digest,
    exclusive,
    private_path,
    source_pin,
    loopback_origin,
    environment,
)
from smoke import local_url


def test_research_sidecars_survive_staged_runtime(tmp_path, monkeypatch):
    from earthsync.research import retrieval

    source = Path(__file__).resolve().parents[3]
    staged = tmp_path / "state"
    staged.mkdir()
    files = copy_research_references(source, staged)
    assert {p.name for p in files} == {
        "integrity.json",
        "facts.json",
        "sources.json",
        "source-receipts.json",
    }
    for path in files:
        assert digest(path) == digest(
            source / "data/crop-rule-candidates/v1" / path.name
        )
    monkeypatch.setattr(
        retrieval, "REVIEW_ROOT", staged / "data/crop-rule-candidates/v1"
    )
    packet = retrieval.EvidenceIndex().retrieve(
        retrieval.EvidenceQuery(crop="rice", question="soil pH")
    )
    assert packet["citations"] and packet["recommendation_eligible"] is False
    assert copy_research_references(tmp_path / "old-source", tmp_path / "unused") == []


@pytest.mark.parametrize(
    "url",
    [
        "https://example.org",
        "http://localhost:8080",
        "http://127.0.0.1:8021@external.invalid",
        "http://127.0.0.1:8021/api",
        "http://127.0.0.1:8021?mock=1",
    ],
)
def test_smoke_rejects_remote_or_ambiguous_origins(url):
    with pytest.raises(argparse.ArgumentTypeError):
        local_url(url)


def test_incomplete_report_never_green(tmp_path):
    report = Report()
    report.add("live NASA", "BLOCKED", "Provider unavailable")
    target = tmp_path / "report.json"
    assert report.write(target) == 2
    assert json.loads(target.read_text())["status"] == "INCOMPLETE"
    with pytest.raises(ValueError):
        report.write(target)


def test_fail_overrides_blocked(tmp_path):
    report = Report()
    report.add("UI", "BLOCKED", "Not run")
    report.check(
        "integrity", lambda: (_ for _ in ()).throw(AssertionError("private data"))
    )
    path = tmp_path / "report.json"
    assert report.write(path) == 1
    assert "private data" not in path.read_text()


def test_running_service_excludes_maintenance_and_releases_lock(tmp_path):
    with exclusive(tmp_path):
        with pytest.raises(ValueError, match="in use"):
            with exclusive(tmp_path):
                pytest.fail("Concurrent maintenance admitted")
    assert not (tmp_path / "operation.lock").exists()
    with pytest.raises(RuntimeError):
        with exclusive(tmp_path):
            raise RuntimeError
    assert not (tmp_path / "operation.lock").exists()


def test_symlink_private_state_rejected(tmp_path):
    link = tmp_path / "link"
    try:
        link.symlink_to(tmp_path, target_is_directory=True)
    except OSError:
        pytest.skip("Creating symlinks unavailable for this account")
    with pytest.raises(ValueError):
        private_path(link)


def test_pin_rejects_dirty_application_and_wrong_sha(tmp_path):
    subprocess.run(["git", "init", str(tmp_path)], check=True, capture_output=True)
    (tmp_path / "server").mkdir()
    target = tmp_path / "server/api.py"
    target.write_text("# tracked\n")
    subprocess.run(["git", "-C", str(tmp_path), "add", "."], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            str(tmp_path),
            "-c",
            "user.name=Ops Test",
            "-c",
            "user.email=ops@example.invalid",
            "commit",
            "-m",
            "fixture",
        ],
        check=True,
        capture_output=True,
    )
    sha = subprocess.check_output(
        ["git", "-C", str(tmp_path), "rev-parse", "HEAD"], text=True
    ).strip()
    assert source_pin(tmp_path, sha) == sha
    with pytest.raises(ValueError, match="SHA"):
        source_pin(tmp_path, "0" * 40)
    target.write_text("# changed\n")
    with pytest.raises(ValueError, match="dirty"):
        source_pin(tmp_path, sha)
    assert len(digest(target)) == 64


def test_state_cannot_contain_source_checkout(tmp_path):
    source = tmp_path / "source"
    source.mkdir()
    result = subprocess.run(
        [
            sys.executable,
            str(Path(__file__).parents[1] / "staging.py"),
            "verify",
            "--source",
            str(source),
            "--state",
            str(tmp_path),
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 2
    assert "must not overlap" in result.stderr
    assert not (tmp_path / "operation.lock").exists()


@pytest.mark.parametrize(
    "value",
    [
        "https://example.org",
        "http://0.0.0.0:8080",
        "http://127.0.0.1:8021@evil.example",
        "http://127.0.0.1:8021/path",
        "http://127.0.0.1:8021?private=1",
        "http://127.0.0.1:80",
        "http://127.0.0.1:bad",
    ],
)
def test_final_build_rejects_nonlocal_platform_and_browser_origins(value):
    with pytest.raises(argparse.ArgumentTypeError):
        loopback_origin(value)


def test_final_platform_environment_uses_exact_recorded_web_origin(tmp_path):
    manifest = {
        "profile": "platform",
        "engine": "/reviewed/v03",
        "catalog": "/reviewed/catalog",
        "files": {"/reviewed/v03": "a" * 64, "/reviewed/catalog": "b" * 64},
        "web_origin": "http://127.0.0.1:8091",
    }
    env = environment(tmp_path / "source", tmp_path / "state", manifest)
    assert env["EARTHSYNC_PLATFORM_ORIGINS"] == "http://127.0.0.1:8091"
    assert env["EARTHSYNC_V03_SHA256"] == "a" * 64
    assert env["EARTHSYNC_PLATFORM_LOCAL"] == "1"
    assert loopback_origin("http://127.0.0.1:8021/") == "http://127.0.0.1:8021"


def test_complete_recovery_rehearsal_uses_current_migration_set(tmp_path):
    from database_check import exercise

    report = Report()
    exercise(report, tmp_path)
    result = report.write(tmp_path / "recovery-report.json")
    if os.name == "nt":
        # chmod cannot establish Windows ACLs. Preserve this explicit manual
        # gate while asserting that every portable recovery check passed.
        assert result == 2
        blocked = [check for check in report.checks if check["status"] == "BLOCKED"]
        assert len(blocked) == 1 and blocked[0]["name"] == "private permissions"
        assert all(check["status"] in ("PASS", "BLOCKED") for check in report.checks)
    else:
        assert result == 0
