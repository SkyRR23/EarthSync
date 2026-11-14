import argparse
import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parents[1]))
from report import Report
from staging import digest, exclusive, private_path, source_pin
from smoke import local_url


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
