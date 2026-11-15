import io
import json
import time
from pathlib import Path
from uuid import uuid4

import pytest
from PIL import Image
from fastapi.testclient import TestClient

from earthsync.research.api import PREFIX, create_app
from earthsync.research.storage import ResearchStore, SCOPES


def upload(client, credential, png):
    response = client.post(
        PREFIX + "/photos",
        params={"farm_id": credential["farm_ids"][0]},
        content=png,
        headers={"content-type": "image/png"},
    )
    assert response.status_code == 201
    return response.json()


@pytest.mark.parametrize("kind", ["missing", "invalid", "expired", "revoked"])
def test_authentication(research_client, research_store, credential, kind):
    if kind == "missing":
        research_client.headers.pop("authorization")
    elif kind == "invalid":
        research_client.headers["authorization"] = "Bearer invalid"
    elif kind == "expired":
        with research_store.connection() as db:
            db.execute("UPDATE credentials SET expires=0")
    else:
        research_store.revoke(credential["key_id"])
    response = research_client.get(PREFIX + "/health")
    assert response.status_code == 401
    assert response.json() == {"error": {"code": "UNAUTHORIZED", "retryable": False}}


def test_scopes_do_not_grant_private_access(
    research_client, research_store, credential, png
):
    photo = upload(research_client, credential, png)
    limited = research_store.provision(
        "synthetic-test",
        "alice",
        ["crop:evidence:read"],
        time.time() + 60,
        credential["farm_ids"],
    )
    research_client.headers["authorization"] = "Bearer " + limited["token"]
    assert (
        research_client.post(
            PREFIX + "/crops/search", json={"query": "rice"}
        ).status_code
        == 200
    )
    assert (
        research_client.get(
            PREFIX + f"/photos/{photo['id']}/image",
            params={"farm_id": photo["farm_id"]},
        ).status_code
        == 403
    )
    assert (
        research_client.post(
            PREFIX + "/photos", params={"farm_id": photo["farm_id"]}, content=png
        ).status_code
        == 403
    )


@pytest.mark.parametrize(
    "tenant,subject", [("other-tenant", "alice"), ("synthetic-test", "bob")]
)
def test_cross_tenant_and_user_denied(
    research_client, research_store, credential, png, tenant, subject
):
    photo = upload(research_client, credential, png)
    other = research_store.provision(tenant, subject, SCOPES, time.time() + 60)
    research_client.headers["authorization"] = "Bearer " + other["token"]
    for farm in (photo["farm_id"], other["farm_ids"][0]):
        assert (
            research_client.get(
                PREFIX + f"/photos/{photo['id']}/image", params={"farm_id": farm}
            ).status_code
            == 404
        )
        assert (
            research_client.post(
                PREFIX + f"/photos/{photo['id']}/analyze", json={"farm_id": farm}
            ).status_code
            == 404
        )
    assert (
        research_client.post(
            PREFIX + "/soil/context", json={"farm_id": photo["farm_id"]}
        ).status_code
        == 404
    )


def test_same_owner_keys_still_need_exact_farm_grant(
    research_client, research_store, credential, png
):
    photo = upload(research_client, credential, png)
    other = research_store.provision(
        "synthetic-test", "alice", SCOPES, time.time() + 60
    )
    research_client.headers["authorization"] = "Bearer " + other["token"]
    assert (
        research_client.get(
            PREFIX + f"/photos/{photo['id']}/image",
            params={"farm_id": photo["farm_id"]},
        ).status_code
        == 404
    )


def test_png_read_analyze_delete_and_restore(
    research_client, research_store, credential, png, tmp_path
):
    photo = upload(research_client, credential, png)
    params = {"farm_id": photo["farm_id"]}
    route = PREFIX + f"/photos/{photo['id']}"
    response = research_client.get(route + "/image", params=params)
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["content-type"] == "image/png"
    result = research_client.post(route + "/analyze", json=params).json()
    assert result["status"] == "unavailable"
    assert result["measurements"] == []
    assert result["chemical_measurements_available"] is False
    research_store.backup(tmp_path / "copy.sqlite3")
    restored_dir = tmp_path / "restored"
    restored_dir.mkdir(mode=0o700)
    (restored_dir / "research.sqlite3").write_bytes(
        (tmp_path / "copy.sqlite3").read_bytes()
    )
    restored = ResearchStore(restored_dir)
    principal = restored.authenticate(credential["token"])
    assert (
        restored.photo(principal, photo["farm_id"], photo["id"])[1] == response.content
    )
    research_store.revoke(credential["key_id"])
    # Restoring an old backup restores its credentials too: documented mandatory revocation/rotation.
    assert restored.authenticate(credential["token"])


def test_image_delete_cascades_reports(research_client, credential, png):
    photo = upload(research_client, credential, png)
    extracted = research_client.post(
        PREFIX + "/lab-reports/extract",
        json={"farm_id": photo["farm_id"], "photo_id": photo["id"]},
    )
    assert extracted.status_code == 201
    route = PREFIX + f"/photos/{photo['id']}"
    assert (
        research_client.delete(route, params={"farm_id": photo["farm_id"]}).status_code
        == 204
    )
    assert (
        research_client.get(
            route + "/image", params={"farm_id": photo["farm_id"]}
        ).status_code
        == 404
    )
    assert (
        research_client.get(
            PREFIX + f"/lab-reports/{extracted.json()['id']}",
            params={"farm_id": photo["farm_id"]},
        ).status_code
        == 404
    )


@pytest.mark.parametrize(
    "raw,mime",
    [
        (b"bad", "image/png"),
        (b"\x89PNG\r\n\x1a\ncorrupt", "image/png"),
        (b"<svg></svg>", "image/jpeg"),
    ],
)
def test_bad_images(research_client, credential, raw, mime):
    assert (
        research_client.post(
            PREFIX + "/photos",
            params={"farm_id": credential["farm_ids"][0]},
            content=raw,
            headers={"content-type": mime},
        ).status_code
        == 422
    )


def test_mime_spoof_and_size_limit(research_client, credential, png):
    path = PREFIX + "/photos?farm_id=" + credential["farm_ids"][0]
    assert (
        research_client.post(
            path, content=png, headers={"content-type": "image/jpeg"}
        ).status_code
        == 422
    )
    assert (
        research_client.post(path, content=b"x" * (10 * 1024 * 1024 + 1)).status_code
        == 413
    )
    assert (
        research_client.post(PREFIX + "/crops/search", content=b"x" * 65537).status_code
        == 413
    )


def test_chunked_upload_limit(research_client, credential):
    def chunks():
        for _ in range(11):
            yield b"x" * 1024 * 1024

    assert (
        research_client.post(
            PREFIX + "/photos",
            params={"farm_id": credential["farm_ids"][0]},
            content=chunks(),
            headers={"content-type": "image/png"},
        ).status_code
        == 413
    )


def test_jpeg_metadata_removed(research_client, credential):
    image = Image.new("RGB", (40, 30), "brown")
    exif = Image.Exif()
    exif[270] = "private farm description"
    stream = io.BytesIO()
    image.save(stream, format="JPEG", exif=exif)
    response = research_client.post(
        PREFIX + "/photos",
        params={"farm_id": credential["farm_ids"][0]},
        content=stream.getvalue(),
        headers={"content-type": "image/jpeg"},
    )
    assert response.status_code == 201
    data = response.json()
    raw = research_client.get(
        PREFIX + f"/photos/{data['id']}/image", params={"farm_id": data["farm_id"]}
    ).content
    with Image.open(io.BytesIO(raw)) as clean:
        assert not clean.getexif()
        assert not clean.info
    assert b"private farm description" not in raw


def test_host_origin_ssrf_and_validation(research_client, credential):
    assert (
        research_client.get(
            PREFIX + "/health", headers={"host": "evil.example"}
        ).status_code
        == 403
    )
    assert (
        research_client.get(
            PREFIX + "/health", headers={"origin": "https://evil.example"}
        ).status_code
        == 403
    )
    assert (
        research_client.post(
            PREFIX + "/crops/evidence",
            json={"crop": "rice", "url": "http://169.254.169.254/"},
        ).status_code
        == 422
    )
    assert research_client.get(
        PREFIX + "/photos/..%2Fsecret/image",
        params={"farm_id": credential["farm_ids"][0]},
    ).status_code in (404, 422)
    assert (
        research_client.get(
            PREFIX + f"/photos/{uuid4()}/image",
            params={"farm_id": credential["farm_ids"][0]},
        ).status_code
        == 404
    )


def test_https_and_cors_config(research_store, evidence_index):
    app = create_app(
        store=research_store, index=evidence_index, allowed_hosts=("testserver",)
    )
    with TestClient(app) as client:
        assert client.get(PREFIX + "/health").status_code == 403
    with pytest.raises(ValueError):
        create_app(store=research_store, index=evidence_index, allowed_origins=("*",))


def test_persistent_per_key_rate_limit(research_store, credential, evidence_index):
    for _ in range(2):
        app = create_app(
            store=research_store,
            index=evidence_index,
            allowed_hosts=("testserver",),
            require_https=False,
            rate_limit=1,
        )
        with TestClient(app) as client:
            response = client.get(
                PREFIX + "/health",
                headers={"authorization": "Bearer " + credential["token"]},
            )
            assert response.status_code == (200 if _ == 0 else 429)


def test_evidence_compare_and_no_secret_leaks(
    research_client, research_store, credential
):
    response = research_client.post(
        PREFIX + "/crops/compare", json={"crops": ["rice", "maize"], "question": "soil"}
    )
    assert response.status_code == 200 and response.json()["ranking"] is None
    assert all(not c["recommendation_eligible"] for c in response.json()["crops"])
    assert credential["token"] not in response.text
    with research_store.connection() as db:
        audit = json.dumps([dict(r) for r in db.execute("SELECT * FROM audit")])
        assert credential["token"] not in audit
        assert credential["token"].encode() not in research_store.path.read_bytes()


def test_no_state_in_checkout_or_symlinks(tmp_path):
    with pytest.raises(ValueError):
        ResearchStore(Path(__file__).resolve().parents[3] / "state")
    target = tmp_path / "target"
    target.mkdir()
    link = tmp_path / "linked"
    link.symlink_to(target, target_is_directory=True)
    with pytest.raises(ValueError):
        ResearchStore(link)
