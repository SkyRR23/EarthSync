import io
import time

import pytest
from PIL import Image
from fastapi.testclient import TestClient

from earthsync.research.api import create_app
from earthsync.research.retrieval import EvidenceIndex
from earthsync.research.storage import ResearchStore, SCOPES


@pytest.fixture(scope="session")
def evidence_index():
    return EvidenceIndex()


@pytest.fixture
def research_store(tmp_path):
    return ResearchStore(tmp_path / "research")


@pytest.fixture
def credential(research_store):
    return research_store.provision(
        "synthetic-test", "alice", SCOPES, time.time() + 3600
    )


@pytest.fixture
def research_client(research_store, credential, evidence_index):
    app = create_app(
        store=research_store,
        index=evidence_index,
        allowed_hosts=("testserver",),
        require_https=False,
    )
    with TestClient(app) as client:
        client.headers["authorization"] = "Bearer " + credential["token"]
        yield client


@pytest.fixture
def png():
    stream = io.BytesIO()
    Image.new("RGB", (32, 32), "brown").save(stream, format="PNG")
    return stream.getvalue()
