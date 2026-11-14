import pytest

from earthsync.evidence.store import PhotoStore


@pytest.fixture
def store(tmp_path):
    return PhotoStore(tmp_path / "private")
