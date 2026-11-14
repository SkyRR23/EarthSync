import pytest


@pytest.fixture
def store(tmp_path):
    from earthsync.evidence.store import PhotoStore

    return PhotoStore(tmp_path / "private")
