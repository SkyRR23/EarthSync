"""Synthetic ZIPs test safe inventory and byte comparison only."""

import hashlib
import stat
import zipfile

import pytest

from inventory_zip import inventory


def test_all_members_hashed_without_executing_source(tmp_path):
    archive = tmp_path / "synthetic.zip"
    data = {
        "data.csv": b"date,value\n2024-01-01,\n",
        "code.py": b"raise RuntimeError('must not execute')\n",
        "build.exe": b"MZuntrusted",
    }
    with zipfile.ZipFile(archive, "w") as out:
        for name, raw in data.items():
            out.writestr(name, raw)
    before = archive.read_bytes()
    result = inventory(archive)
    assert result["archive_sha256"] == hashlib.sha256(before).hexdigest()
    assert archive.read_bytes() == before
    assert len(result["members"]) == 3
    assert all(
        row["sha256"] == hashlib.sha256(data[row["path"]]).hexdigest()
        for row in result["members"]
    )
    assert result["members"][0]["empty_cells"] == 1
    assert result["members"][2]["category"] == "compiled_artifact_rejected"
    renamed = tmp_path / "renamed.zip"
    with zipfile.ZipFile(renamed, "w") as out:
        out.writestr("prefix/data.csv", data["data.csv"])
    assert inventory(renamed, result)["members"][0]["same_bytes_in_pr11"] == [
        "data.csv"
    ]


@pytest.mark.parametrize("name", ["../escape", "/absolute", "a\\b", "C:/drive"])
def test_unsafe_paths_rejected(tmp_path, name):
    archive = tmp_path / "synthetic.zip"
    with zipfile.ZipFile(archive, "w") as out:
        out.writestr(name, b"x")
    with pytest.raises(ValueError):
        inventory(archive)


def test_symbolic_link_rejected(tmp_path):
    archive = tmp_path / "synthetic.zip"
    with zipfile.ZipFile(archive, "w") as out:
        link = zipfile.ZipInfo("link")
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        out.writestr(link, "target")
    with pytest.raises(ValueError):
        inventory(archive)
