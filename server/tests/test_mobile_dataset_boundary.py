"""Build input guard: server rasters and global crop data must stay off devices."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_mobile_assets_exclude_large_scientific_datasets():
    prohibited = {".tif", ".tiff", ".hdf", ".h5", ".nc", ".grib", ".grib2", ".sqlite3"}
    for file in (ROOT / "app/assets").rglob("*"):
        assert file.suffix.lower() not in prohibited, (
            f"Server dataset entered app assets: {file}"
        )
    manifest = (ROOT / "app/pubspec.yaml").read_text(encoding="utf-8")
    assert "../data/" not in manifest
    assert "../server/" not in manifest
    assert "datasets/" not in manifest
