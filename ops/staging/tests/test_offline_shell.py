"""Offline shell contains public build assets, never private runtime endpoints."""

import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[3]
spec = importlib.util.spec_from_file_location(
    "offline_shell", ROOT / "scripts/finalize_offline.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_public_static_allowlist_and_deterministic_hash(tmp_path):
    (tmp_path / "index.html").write_text("<html>Build one</html>")
    (tmp_path / "main.dart.js").write_text("console.log('build one')")
    (tmp_path / "api").mkdir()
    (tmp_path / "api/private.json").write_text('{"secret":"not for static cache"}')
    (tmp_path / "platform.sqlite3").write_bytes(b"private data")
    (tmp_path / "assets").mkdir()
    (tmp_path / "assets/font.ttf").write_bytes(b"synthetic font fixture")
    result = module.finalize(tmp_path)
    assert set(result["public_assets"]) == {
        "index.html",
        "main.dart.js",
        "assets/font.ttf",
    }
    assert result["private_api_cached"] is False
    assert module.finalize(tmp_path) == result
    worker = (tmp_path / "earthsync-offline.js").read_text()
    assert "request.method !== 'GET'" in worker
    assert "!allowed.has(key)" in worker
    assert "private.json" not in worker
    assert "platform.sqlite3" not in worker
    assert "skipWaiting" not in worker
    assert json.loads((tmp_path / "offline-assets.json").read_text()) == result
    (tmp_path / "main.dart.js").write_text("console.log('build two')")
    assert module.finalize(tmp_path)["build_sha256"] != result["build_sha256"]


def test_private_database_in_assets_is_rejected(tmp_path):
    (tmp_path / "index.html").write_text("<html></html>")
    (tmp_path / "main.dart.js").write_text("")
    (tmp_path / "assets").mkdir()
    (tmp_path / "assets/farm.sqlite3").write_bytes(b"private")
    with pytest.raises(ValueError, match="Private files"):
        module.finalize(tmp_path)
