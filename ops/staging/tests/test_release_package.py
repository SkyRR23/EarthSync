"""Packaging tests use synthetic source, binary signatures and Web fixtures."""

import importlib.util
import json
import platform
from pathlib import Path
import subprocess
import zipfile

import pytest

ROOT = Path(__file__).resolve().parents[3]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / f"scripts/{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


package = load("package_release")
offline = load("finalize_offline")


@pytest.fixture
def release(tmp_path, monkeypatch):
    source = tmp_path / "checkout"
    source.mkdir()
    (source / "server").mkdir()
    (source / "server/runtime.py").write_text("# SYNTHETIC runtime source\n")
    (source / "scripts").mkdir()
    (source / "scripts/start.py").write_text("# SYNTHETIC startup source\n")
    for args in [
        ["init"],
        ["add", "."],
        [
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "commit",
            "-m",
            "Synthetic fixture",
        ],
    ]:
        subprocess.run(
            ["git", "-C", str(source), *args], check=True, capture_output=True
        )
    sha = package.git(source, "rev-parse", "HEAD").decode().strip()
    monkeypatch.setattr(package, "SOURCE_PATHS", ["server", "scripts"])
    web = source / "app/build/web"
    web.mkdir(parents=True)
    (web / "index.html").write_text("<html>SYNTHETIC Web build</html>")
    (web / "main.dart.js").write_text(
        "console.log('SYNTHETIC build http://127.0.0.1:8021')"
    )
    offline.finalize(web)
    # Neither untracked files nor another local branch's source enters the zip.
    (source / "private.sqlite3").write_bytes(b"SYNTHETIC private data")
    (source / "server/untracked-token.txt").write_text(
        "SYNTHETIC not an authorization token"
    )
    native = tmp_path / "native"
    native.write_bytes(
        (b"MZ" if platform.system() == "Windows" else b"\x7fELF") + b" SYNTHETIC binary"
    )
    return source, sha, tmp_path / "release.zip", native


def build(release):
    source, sha, output, native = release
    return package.build(source, sha, output, native, native)


def unpack(release):
    directory = release[0].parent / "unpacked"
    with zipfile.ZipFile(release[2]) as archive:
        archive.extractall(directory)
    return directory


def test_complete_package_preserves_hashes_without_private_or_untracked_files(release):
    manifest, checksum = build(release)
    directory = unpack(release)
    assert package.verify(directory, release[1]) == manifest
    assert checksum == package.digest(release[2].read_bytes())
    assert release[2].with_suffix(".zip.sha256").read_text().startswith(checksum)
    assert not any(
        "private" in name or "token" in name or ".git/" in name
        for name in manifest["files"]
    )
    assert "source/server/runtime.py" in manifest["files"]
    assert "source/app/build/web/main.dart.js" in manifest["files"]
    assert (
        len([name for name in manifest["files"] if "/target/debug/examples/" in name])
        == 2
    )


@pytest.mark.parametrize(
    "fault",
    [
        "tampered",
        "missing",
        "extra",
        "traversal",
        "wrong-host",
        "wrong-sha",
        "public-url",
    ],
)
def test_verifier_rejects_incomplete_changed_or_wrong_target_package(release, fault):
    build(release)
    directory = unpack(release)
    manifest = directory / "release.json"
    if fault == "tampered":
        (directory / "source/server/runtime.py").write_text("changed")
    elif fault == "missing":
        (directory / "source/server/runtime.py").unlink()
    elif fault == "extra":
        (directory / "source/private.sqlite3").write_bytes(b"not a deployable asset")
    else:
        data = json.loads(manifest.read_text())
        if fault == "traversal":
            data["files"]["../outside"] = {"sha256": "0" * 64, "bytes": 0}
        elif fault == "wrong-host":
            data["system"] = "Unsupported target"
        elif fault == "public-url":
            data["platform_url"] = "https://untrusted.invalid"
        else:
            data["source_sha"] = "0" * 40
        manifest.write_text(json.dumps(data))
    with pytest.raises(ValueError):
        package.verify(directory, release[1])


def test_packager_rejects_dirty_source_and_wrong_sha(release):
    source, sha, output, native = release
    with pytest.raises(ValueError, match="reviewed SHA"):
        package.build(source, "0" * 40, output, native, native)
    (source / "server/runtime.py").write_text("unreviewed edit")
    with pytest.raises(ValueError, match="clean"):
        build(release)


@pytest.mark.parametrize("fault", ["unlisted", "changed", "private"])
def test_packager_rejects_unlisted_or_changed_web_assets(release, fault):
    web = release[0] / "app/build/web"
    if fault == "unlisted":
        (web / "private.sqlite3").write_text("SYNTHETIC private data")
    elif fault == "changed":
        (web / "main.dart.js").write_text("changed")
    else:
        (web / "assets").mkdir()
        (web / "assets/private.db").write_text("SYNTHETIC private data")
    with pytest.raises(ValueError):
        build(release)


def test_packager_preserves_existing_output_and_refuses_source_destination(release):
    build(release)
    previous = release[2].read_bytes()
    with pytest.raises(ValueError, match="Preserve"):
        build(release)
    assert release[2].read_bytes() == previous
    with pytest.raises(ValueError, match="outside"):
        package.build(
            release[0], release[1], release[0] / "release.zip", release[3], release[3]
        )


def test_packager_refuses_symlinked_public_assets(release):
    if platform.system() == "Windows":
        pytest.skip("Windows symlink creation privilege is not assumed")
    web = release[0] / "app/build/web"
    (web / "index.html").unlink()
    (web / "index.html").symlink_to(release[0] / "server/runtime.py")
    with pytest.raises(ValueError, match="symlinked"):
        build(release)


def test_packager_rejects_a_web_build_for_another_backend(release):
    web = release[0] / "app/build/web"
    (web / "main.dart.js").write_text(
        "console.log('SYNTHETIC https://example.invalid')"
    )
    offline.finalize(web)
    with pytest.raises(ValueError, match="PLATFORM_URL"):
        build(release)


def test_runtime_snapshot_includes_every_7v_pinned_scientific_input():
    pins = json.loads(
        (ROOT / "data/crop-rule-candidates/v1/input-pins.json").read_text()
    )["files"]
    selected = set(
        package.git(ROOT, "ls-files", "--", *package.SOURCE_PATHS).decode().splitlines()
    )
    assert set(pins) <= selected
    assert "docs/integration/7p/HANDOFF_7J.md" in selected
