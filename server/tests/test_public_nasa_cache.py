"""Previously retrieved real public point/cell data; this is not a live test."""

from copy import deepcopy

from earthsync.realtime.public_cache import seed, SOURCE_SHA


class Repository:
    def __init__(self):
        self.records = {}

    def get(self, key):
        return self.records.get(key)

    def put(self, key, value):
        self.records[key] = deepcopy(value)


def test_pinned_real_receipts_retain_times_and_are_not_an_overlay():
    repository = Repository()
    repository.records["source:ames:imerg"] = {
        "data": None,
        "error": "AUTHENTICATION_REQUIRED",
    }
    assert seed(repository) == 3
    for value in repository.records.values():
        assert value["error"] == "IMPORTED_VERIFIED_RELEASE_CACHE"
        assert value["data"]["numeric_observation"] is True
        assert value["data"]["cached_source_release"]["git_sha"] == SOURCE_SHA
        assert "png_base64" not in value["data"]
    ndvi = repository.records["source:ames:hls_ndvi"]["data"]
    assert ndvi["value"] == 0.539
    assert ndvi["acquired_start"].startswith("2026-10-22T17:12:07")
    assert seed(repository) == 0  # Existing state is never overwritten.


def test_unrecognized_or_missing_capture_is_not_imported(tmp_path):
    repository = Repository()
    assert seed(repository, tmp_path / "missing.json") == 0
    fake = tmp_path / "fake.json"
    fake.write_text('{"pretend": "current weather"}')
    assert seed(repository, fake) == 0
    assert not repository.records
