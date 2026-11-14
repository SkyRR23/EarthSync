import hashlib
import importlib.util
import io
import os
import sys
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from earthsync.platform_v1.api import PREFIX, create_app
from earthsync.platform_v1.catalog import Catalog
from earthsync.platform_v1.engine import RustEngine
from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.models import AssessmentInput
from earthsync.platform_v1.objects import LocalObjects
from earthsync.platform_v1.orchestrate import Orchestrator


class Offline:
    async def get(self, *args):
        raise PlatformError("OUTBOUND_PROXY_BLOCKED", 503)


def local_client(store, **kwargs):
    app = create_app(store=store, transport=Offline(), local_enabled=True, **kwargs)
    return TestClient(app, base_url="http://127.0.0.1", client=("127.0.0.1", 10000))


def test_default_disabled_and_local_boundary(store):
    with pytest.raises(ValueError):
        create_app(store=store)
    app = create_app(store=store, transport=Offline(), local_enabled=True)
    with TestClient(
        app, base_url="http://127.0.0.1", client=("192.168.1.5", 10000)
    ) as client:
        assert client.get(PREFIX + "/health").status_code == 403
    with TestClient(
        app, base_url="http://127.0.0.1", client=("127.0.0.1", 10000)
    ) as client:
        assert (
            client.get(PREFIX + "/health", headers={"Host": "evil.example"}).status_code
            == 403
        )
        assert (
            client.get(
                PREFIX + "/health", headers={"Origin": "https://evil.example"}
            ).status_code
            == 403
        )
        assert client.get(PREFIX + "/health").status_code == 200
        response = client.get(PREFIX + "/ready")
        assert response.status_code == 503
        assert not response.json()["hosted_private_api_enabled"]


def test_cors_rate_limit_and_safe_input_errors(store):
    with pytest.raises(ValueError):
        create_app(store=store, local_enabled=True, allowed_origins=("*",))
    with local_client(store, rate_limit=2) as client:
        response = client.post(PREFIX + "/farms", json={"private_coordinate": "SECRET"})
        assert response.status_code == 422
        assert "SECRET" not in response.text
        assert client.get(PREFIX + "/health").status_code == 200
        assert client.get(PREFIX + "/health").status_code == 429


def test_oversized_raw_stream(store):
    with local_client(store) as client:
        response = client.post(
            PREFIX + "/farms",
            content=b"x" * 2_000_001,
            headers={"Content-Type": "application/json"},
        )
        assert response.status_code == 413


def test_farm_evidence_history_and_openapi(store, farm_input):
    with local_client(store) as client:
        farm = client.post(PREFIX + "/farms", json=farm_input.model_dump(mode="json"))
        assert farm.status_code == 201
        ident = farm.json()["id"]
        assert (
            client.get(PREFIX + "/farms/" + ident).json()["confirmed_point"]
            == farm_input.confirmed_point.model_dump()
        )
        assert len(client.get(PREFIX + "/farms").json()) == 1
        assert client.get(PREFIX + f"/farms/{ident}/decisions").json() == []
        assert client.get(PREFIX + "/evidence/unknown").status_code == 404
        assert client.get(PREFIX + f"/farms/{uuid4()}").status_code == 404
        docs = client.get("/openapi.json").json()
        assert PREFIX + "/assessments" in docs["paths"]
        assert PREFIX + "/climate/jobs" in docs["paths"]


def test_regional_climate_job_without_farm(store, query):
    with local_client(store) as client:
        job = client.post(
            PREFIX + "/climate/jobs", json={"query": query.model_dump(mode="json")}
        )
        assert job.status_code == 202
        ident = job.json()["id"]

        async def wait():
            await client.app.state.jobs.queue.join()

        client.portal.call(wait)
        response = client.get(PREFIX + "/jobs/" + ident).json()
        assert response["status"] == "succeeded"
        assert response["result"]["records"] == []
        assert len(response["result"]["gaps"]) == 3
        assert client.get(PREFIX + "/providers").json()["sources"]


def test_farm_environmental_jobs(store, farm_input, query):
    with local_client(store) as client:
        farm = client.post(
            PREFIX + "/farms", json=farm_input.model_dump(mode="json")
        ).json()
        for path, body in [
            ("/soil/jobs", {"point": query.point.model_dump(), "farm_id": farm["id"]}),
            (
                "/optical/jobs",
                {
                    "farm_id": farm["id"],
                    "start": "2024-02-01T00:00:00Z",
                    "end": "2024-02-29T23:59:59Z",
                },
            ),
        ]:
            response = client.post(PREFIX + path, json=body)
            assert response.status_code == 202

            async def wait():
                await client.app.state.jobs.queue.join()

            client.portal.call(wait)
            job = client.get(PREFIX + "/jobs/" + response.json()["id"]).json()
            assert job["status"] == "failed"
            assert job["error"] == "OUTBOUND_PROXY_BLOCKED"
        wrong = query.model_copy(deep=True)
        wrong.point.latitude = 0
        assert (
            client.post(
                PREFIX + "/climate/jobs",
                json={"query": wrong.model_dump(mode="json"), "farm_id": farm["id"]},
            ).status_code
            == 422
        )


def test_catalog_compatibility_and_eligibility(compat_sources):
    path = compat_sources / "15/data/crop-knowledge/v1/catalog.json"
    catalog = Catalog(path, hashlib.sha256(path.read_bytes()).hexdigest())
    profile, sidecar = catalog.project(
        "us_ia_story_corn_rainfed_v1", "us_ia_story", "rainfed"
    )
    assert profile["review"] == "reference_only"
    assert profile["rules"] == []
    assert not profile["approved_for_candidates"]
    assert not sidecar["recommendation_eligible"]
    with pytest.raises(PlatformError, match="PROFILE_SCOPE_MISMATCH"):
        catalog.project(profile["id"], "au_riverina", "rainfed")
    with pytest.raises(PlatformError, match="PRODUCTION_SYSTEM_MISMATCH"):
        catalog.project(profile["id"], "us_ia_story", "irrigated")
    with pytest.raises(ValueError):
        Catalog(path, "0" * 64)


def rust_engine():
    path = os.getenv("EARTHSYNC_TEST_V03")
    if not path:
        pytest.skip(
            "Set EARTHSYNC_TEST_V03 to actual pinned PR #18 v03_demo executable"
        )
    return RustEngine(path, hashlib.sha256(Path(path).read_bytes()).hexdigest())


async def test_actual_rust_v03_and_reference_catalog(
    store, farm_input, records, compat_sources
):
    engine = rust_engine()
    farm = store.create_farm("alice", farm_input)
    for record in records:
        store.save_evidence("alice", record, farm.id)
    path = compat_sources / "15/data/crop-knowledge/v1/catalog.json"
    catalog = Catalog(path, hashlib.sha256(path.read_bytes()).hexdigest())
    query = AssessmentInput(
        farm_id=farm.id,
        evidence_ids=[r.id for r in records],
        profile_ids=["us_ia_story_corn_rainfed_v1"],
        pilot_id="us_ia_story",
        start="2024-02-01",
        end="2024-02-29",
    )
    result = await Orchestrator(store, engine, catalog).assess("alice", query)
    assert result["result"]["status"] == "success"
    assert not result["recommendation_eligible"]
    context = result["result"]["data"]["context"]
    assert len(context["climate"]) == 3
    assert all(
        s["provenance"]["spatial"]["scope"] == "regional" for s in context["climate"]
    )
    assert context["approximate_user_location"] is None
    assert context["catalog"][0]["rules"] == []
    assert (
        result["result"]["data"]["summaries"][0]["status"] == "insufficient_information"
    )
    assert {v.get("variable") for v in result["evidence_gaps"]} == {"et0"}
    assert len(store.decisions("alice", farm.id)) == 1
    with pytest.raises(PlatformError, match="NOT_FOUND"):
        await Orchestrator(store, engine, catalog).assess("bob", query)


async def test_actual_rust_missing_evidence_api(store, farm_input):
    engine = rust_engine()
    with local_client(store, engine=engine) as client:
        farm = client.post(
            PREFIX + "/farms", json=farm_input.model_dump(mode="json")
        ).json()
        response = client.post(
            PREFIX + "/assessments",
            json={"farm_id": farm["id"], "start": "2024-02-01", "end": "2024-02-29"},
        )
        assert response.status_code == 200, response.text
        assert response.json()["result"]["status"] == "success"
        assert len(response.json()["evidence_gaps"]) == 5
        assert client.get(PREFIX + "/ready").status_code == 200


async def test_incompatible_evidence_rejected_before_engine(store, farm_input, records):
    farm = store.create_farm("alice", farm_input)
    store.save_evidence("alice", records[0], farm.id)
    changed = records[0].model_copy(deep=True)
    changed.id = "ev_" + "f" * 64
    store.save_evidence("alice", changed, farm.id)
    query = AssessmentInput(
        farm_id=farm.id,
        evidence_ids=[records[0].id, changed.id],
        start="2024-02-01",
        end="2024-02-29",
    )
    with pytest.raises(PlatformError, match="AMBIGUOUS_EVIDENCE"):
        await Orchestrator(store, RustEngine(), Catalog()).assess("alice", query)


def sanitizer_from_pr16(root):
    path = root / "16/server/earthsync/evidence/images.py"
    spec = importlib.util.spec_from_file_location("audited_pr16_images", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module.sanitize_image


def test_actual_pr16_photo_security_ownership_and_api(
    store, farm_input, compat_sources
):
    sanitizer = sanitizer_from_pr16(compat_sources)
    objects = LocalObjects(store, sanitizer=sanitizer)
    alice = store.create_farm("alice", farm_input)
    bob = store.create_farm("bob", farm_input)
    stream = io.BytesIO()
    image = Image.new("RGB", (8, 8), "red")
    exif = Image.Exif()
    exif[0x010E] = "private coordinates"
    image.save(stream, "JPEG", exif=exif)
    clean = objects.clean(stream.getvalue(), "image/jpeg")
    with Image.open(io.BytesIO(clean.data)) as stored:
        assert not stored.getexif()
        assert not stored.info
    photo = objects.save_photo("alice", alice.id, clean)
    for owner, farm_id in [("bob", alice.id), ("bob", bob.id)]:
        with pytest.raises(PlatformError, match="NOT_FOUND"):
            objects.image(owner, farm_id, photo["id"])
        with pytest.raises(PlatformError, match="NOT_FOUND"):
            objects.delete(owner, farm_id, photo["id"])
    with pytest.raises(PlatformError, match="INVALID_IMAGE"):
        objects.clean(b"not a PNG", "image/png")
    objects.delete("alice", alice.id, photo["id"])
    assert not list(objects.root.iterdir())
    with local_client(store, objects=objects) as client:
        farm = client.post(
            PREFIX + "/farms", json=farm_input.model_dump(mode="json")
        ).json()
        url = PREFIX + f"/farms/{farm['id']}/photos"
        response = client.post(
            url, content=stream.getvalue(), headers={"Content-Type": "image/jpeg"}
        )
        assert response.status_code == 201
        ident = response.json()["id"]
        assert client.get(url + f"/{ident}/image").status_code == 200
        assert client.delete(url + f"/{ident}").status_code == 204
        assert client.get(url + f"/{ident}/image").status_code == 404


def load_pr14(root):
    path = root / "14/server/earthsync/assistant"
    spec = importlib.util.spec_from_file_location(
        "audited_pr14", path / "__init__.py", submodule_search_locations=[str(path)]
    )
    package = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = package
    spec.loader.exec_module(package)
    models = __import__("audited_pr14.models", fromlist=["ChatRequest"])
    service = __import__("audited_pr14.service", fromlist=["explain"])
    return models, service


def test_actual_assistant_with_source_references(
    store, farm_input, records, compat_sources
):
    from earthsync.platform_v1.context import assistant_context

    farm = store.create_farm("alice", farm_input)
    for record in records:
        store.save_evidence("alice", record, farm.id)
    context = assistant_context(store, "alice", farm.id)
    models, service = load_pr14(compat_sources)
    request = models.ChatRequest(
        question="What rainfall evidence is available?", context=context
    )
    result = service.explain(request)
    assert result.citations
    assert all(c.id in {r.id for r in records} for c in result.citations)
    assert all(e.calculation == "none" for e in result.evidence)
    assert all(e.scope == "regional" for e in result.evidence)


def test_complete_object_backup_and_restore(
    store, farm_input, compat_sources, tmp_path
):
    from earthsync.platform_v1.maintenance import backup, restore

    sanitizer = sanitizer_from_pr16(compat_sources)
    objects = LocalObjects(store, sanitizer=sanitizer)
    farm = store.create_farm("owner", farm_input)
    stream = io.BytesIO()
    Image.new("RGB", (4, 4), "green").save(stream, "PNG")
    photo = objects.save_photo(
        "owner", farm.id, objects.clean(stream.getvalue(), "image/png")
    )
    directory = tmp_path / "backup"
    backup(store, directory)
    restored = restore(directory, tmp_path / "restore")
    assert LocalObjects(restored).image("owner", farm.id, photo["id"]) == objects.image(
        "owner", farm.id, photo["id"]
    )
    (directory / "objects" / (photo["id"] + ".png")).write_bytes(b"corrupted")
    with pytest.raises(ValueError, match="checksum"):
        restore(directory, tmp_path / "invalid-restore")


def test_farmer_history_and_context_api(store, farm_input):
    with local_client(store) as client:
        farm = client.post(
            PREFIX + "/farms", json=farm_input.model_dump(mode="json")
        ).json()
        base = PREFIX + f"/farms/{farm['id']}"
        response = client.post(
            base + "/history",
            json={
                "crop_id": "corn@catalog-0.1.0",
                "start": "2023-04-15",
                "end": "2023-10-01",
            },
        )
        assert response.status_code == 201
        assert response.json()["data_type"] == "farmer_reported"
        assert len(client.get(base + "/history").json()) == 1
        assert client.get(base + "/context").json()["agricultural_diagnosis"] is None
        assert (
            client.get(base + "/assistant-context").json()["approximate_location"]
            is None
        )
        response = client.post(
            base + "/history",
            json={
                "crop_id": "corn@1",
                "fallow": True,
                "start": "2023-04-15",
                "end": "2023-10-01",
            },
        )
        assert response.status_code == 422


@pytest.mark.parametrize(
    "program,code",
    [
        ("print('not json')", "RUST_EXECUTION_FAILURE"),
        ("raise SystemExit(2)", "RUST_EXECUTION_FAILURE"),
        ("import time; time.sleep(5)", "RUST_TIMEOUT"),
    ],
)
@pytest.mark.skipif(
    os.name == "nt",
    reason="POSIX test executable; actual compiled Rust is tested on Windows",
)
async def test_process_errors_and_timeout(tmp_path, program, code):
    # Test process transport failure modes with an explicit test-only executable.
    path = tmp_path / "test_process"
    path.write_text(f"#!{sys.executable}\n{program}\n")
    path.chmod(0o700)
    engine = RustEngine(
        path, hashlib.sha256(path.read_bytes()).hexdigest(), timeout=0.1
    )
    with pytest.raises(PlatformError, match=code):
        await engine.analyze({})


async def test_actual_rust_explicit_sequence_conflict(
    store, farm_input, compat_sources
):
    engine = rust_engine()
    farm = store.create_farm("owner", farm_input)
    path = compat_sources / "15/data/crop-knowledge/v1/catalog.json"
    catalog = Catalog(path, hashlib.sha256(path.read_bytes()).hexdigest())
    query = AssessmentInput(
        farm_id=farm.id,
        pilot_id="us_ia_story",
        start="2024-02-01",
        end="2024-02-29",
        sequential_field=True,
        plans=[
            {
                "profile_id": "us_ia_story_corn_rainfed_v1",
                "start": "2024-02-01",
                "end": "2024-02-20",
            },
            {
                "profile_id": "us_ia_story_soybean_rainfed_v1",
                "start": "2024-02-15",
                "end": "2024-02-29",
            },
        ],
    )
    result = await Orchestrator(store, engine, catalog).assess("owner", query)
    findings = result["result"]["data"]["findings"]
    assert any(
        f["rule_id"] == "schedule.sequential"
        and f["status"] == "conflicts_with_supplied_evidence"
        for f in findings
    )
    assert (
        result["result"]["data"]["summaries"][0]["status"]
        == "conflicts_with_supplied_evidence"
    )
    assert not result["recommendation_eligible"]
