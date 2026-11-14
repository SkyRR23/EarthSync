import io
import json
import sqlite3

import httpx
import pytest
from PIL import Image, PngImagePlugin

from earthsync.evidence.app import PREFIX, create_app
from earthsync.evidence.images import MAX_UPLOAD_BYTES, InvalidImage, sanitize_image
from earthsync.evidence.models import PhotoInput
from earthsync.evidence.store import PhotoStore

TOKEN = "test-private-workspace-token-123456789"
META = {"source": "gallery", "category": "crop"}


def png(size=(12, 8), color="green"):
    data = io.BytesIO()
    info = PngImagePlugin.PngInfo()
    info.add_text("GPS", "private coordinates must disappear")
    Image.new("RGB", size, color).save(data, format="PNG", pnginfo=info)
    return data.getvalue()


def headers(metadata=None, mime="image/png"):
    return {
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": mime,
        "X-EarthSync-Metadata": json.dumps(metadata or META, ensure_ascii=True),
    }


@pytest.fixture
async def client(store):
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=create_app(store=store, token=TOKEN)),
        base_url="http://test",
    ) as client:
        yield client


async def test_upload_view_replace_remove_atomic_slice(client, store):
    metadata = {
        **META,
        "caption": "Farmer's photo — စပါး",
        "farmer_observations": "Leaves look yellow to me",
        "captured_date": "2026-11-01",
        "capture_time_source": "farmer_reported",
        "farm": {"farm_id": "farm-global-1", "confirmed_by_farmer": True},
    }
    uploaded = await client.post(
        f"{PREFIX}/photos", headers=headers(metadata), content=png()
    )
    assert uploaded.status_code == 201
    photo = uploaded.json()
    assert photo["schema_version"] == "evidence.v1"
    assert photo["position"] is None
    assert photo["captured_at"] is None
    assert photo["quality"] == "not_scientifically_validated"
    assert photo["metadata_stripped"] is True
    assert photo["farmer_observations"] == metadata["farmer_observations"]
    url = f"{PREFIX}/photos/{photo['id']}"
    auth = {"Authorization": f"Bearer {TOKEN}"}
    image = await client.get(f"{url}/image", headers=auth)
    assert image.status_code == 200
    assert image.headers["cache-control"] == "no-store"
    assert image.headers["x-content-type-options"] == "nosniff"
    with Image.open(io.BytesIO(image.content)) as decoded:
        assert decoded.size == (12, 8)
        assert not decoded.info
        assert not decoded.getexif()
    assert (await client.get(url, headers=auth)).json() == photo
    assert (await client.get(f"{PREFIX}/photos", headers=auth)).json() == [photo]

    invalid = await client.put(url, headers=headers(), content=b"not a photo")
    assert invalid.status_code == 422
    assert (await client.get(url, headers=auth)).json() == photo
    replacement = await client.put(url, headers=headers(), content=png((5, 7), "blue"))
    assert replacement.status_code == 200
    replaced = replacement.json()
    assert replaced["id"] == photo["id"]
    assert replaced["uploaded_at"] == photo["uploaded_at"]
    assert replaced["width_px"] == 5
    assert replaced["farm"] is None
    assert replaced["sha256"] != photo["sha256"]
    assert (await client.delete(url, headers=auth)).status_code == 204
    assert (await client.get(f"{url}/image", headers=auth)).status_code == 404
    assert store.list() == []


@pytest.mark.parametrize(
    "method,path",
    [
        ("get", "/photos"),
        ("post", "/photos"),
        ("get", "/photos/invalid"),
        ("get", "/photos/invalid/image"),
        ("put", "/photos/invalid"),
        ("delete", "/photos/invalid"),
        ("post", "/timeline"),
    ],
)
async def test_all_routes_require_workspace_token(client, method, path):
    response = await client.request(method, PREFIX + path)
    assert response.status_code == 401


@pytest.mark.parametrize(
    "changes",
    [
        {"farm": {"farm_id": "f", "confirmed_by_farmer": False}},
        {
            "position": {
                "latitude": 10,
                "longitude": 10,
                "source": "consented_exif",
                "retention_authorized": False,
            }
        },
        {
            "position": {
                "latitude": 91,
                "longitude": 10,
                "source": "farmer_reported",
                "retention_authorized": True,
            }
        },
        {
            "captured_at": "2026-11-01T12:30:00",
            "capture_time_source": "farmer_reported",
        },
        {"captured_date": "2026-11-01"},
        {"capture_time_source": "farmer_reported"},
        {
            "captured_date": "2026-11-01",
            "captured_at": "2026-11-01T00:00:00Z",
            "capture_time_source": "farmer_reported",
        },
        {"source": "inferred_from_pixels"},
        {"category": "disease_diagnosed"},
        {"schema_version": "evidence.v2"},
        {"filename": "../../secret.png"},
        {"caption": "x" * 1001},
    ],
)
async def test_invalid_metadata_rejected(client, changes):
    response = await client.post(
        f"{PREFIX}/photos", headers=headers({**META, **changes}), content=png()
    )
    assert response.status_code == 422


async def test_separate_authorized_photo_gps_is_never_farm_confirmation(client):
    metadata = {
        **META,
        "position": {
            "latitude": -33.9,
            "longitude": 151.2,
            "source": "consented_exif",
            "retention_authorized": True,
            "uncertainty_m": None,
        },
    }
    response = await client.post(
        f"{PREFIX}/photos", headers=headers(metadata), content=png()
    )
    assert response.status_code == 201
    assert response.json()["farm"] is None
    assert response.json()["position"] == metadata["position"]


@pytest.mark.parametrize(
    "mime,data,status",
    [
        ("image/svg+xml", b"<svg/>", 415),
        ("image/jpeg", png(), 422),
        ("image/png", b"\x89PNG\r\n\x1a\ntruncated", 422),
        ("image/png", b"", 422),
        ("image/png", b"x" * (MAX_UPLOAD_BYTES + 1), 413),
    ],
)
async def test_upload_validation(client, mime, data, status):
    response = await client.post(
        f"{PREFIX}/photos", headers=headers(mime=mime), content=data
    )
    assert response.status_code == status


async def test_chunked_request_is_bounded(client):
    async def chunks():
        for _ in range(11):
            yield b"x" * 1024 * 1024

    response = await client.post(
        f"{PREFIX}/photos", headers=headers(), content=chunks()
    )
    assert response.status_code == 413


def test_dimensions_and_animated_images():
    with pytest.raises(InvalidImage, match="dimension"):
        sanitize_image(png((8193, 1)), "image/png")
    with pytest.raises(InvalidImage, match="dimension"):
        sanitize_image(png((4001, 4000)), "image/png")
    animated = io.BytesIO()
    Image.new("RGB", (3, 3)).save(
        animated,
        format="PNG",
        save_all=True,
        append_images=[Image.new("RGB", (3, 3), "red")],
    )
    with pytest.raises(InvalidImage, match="single-frame"):
        sanitize_image(animated.getvalue(), "image/png")


def test_jpeg_orientation_and_sensitive_metadata_removed():
    exif = Image.Exif()
    exif[274] = 6
    exif[270] = "private caption"
    exif[34853] = {1: "N", 2: (16.0, 48.0, 0.0), 3: "E", 4: (96.0, 9.0, 0.0)}
    data = io.BytesIO()
    Image.new("RGB", (12, 8), "green").save(data, format="JPEG", exif=exif)
    clean = sanitize_image(data.getvalue(), "image/jpeg")
    assert (clean.width, clean.height) == (8, 12)
    with Image.open(io.BytesIO(clean.data)) as image:
        assert not image.info
        assert not image.getexif()


async def test_quota_failure_does_not_replace_old_photo(client, store):
    original = (
        await client.post(f"{PREFIX}/photos", headers=headers(), content=png())
    ).json()
    store.capacity_bytes = original["size_bytes"]
    url = f"{PREFIX}/photos/{original['id']}"
    response = await client.put(url, headers=headers(), content=png((100, 100)))
    assert response.status_code == 507
    assert store.get(original["id"]).model_dump(mode="json") == original


def test_storage_permissions_and_no_user_paths(store, tmp_path):
    assert store.path.stat().st_mode & 0o777 == 0o600
    assert store.path.parent.stat().st_mode & 0o777 == 0o700
    with pytest.raises(ValueError):
        PhotoStore(tmp_path / ".." / "escape")
    link = tmp_path / "symlink"
    link.symlink_to(store.path.parent, target_is_directory=True)
    with pytest.raises(ValueError):
        PhotoStore(link)
    with sqlite3.connect(store.path) as db:
        assert db.execute("SELECT COUNT(*) FROM photos").fetchone()[0] == 0


def test_service_fails_closed_without_private_configuration(store, monkeypatch):
    monkeypatch.delenv("EARTHSYNC_EVIDENCE_TOKEN", raising=False)
    with pytest.raises(ValueError, match="token"):
        create_app(store=store)
    with pytest.raises(ValueError, match="token"):
        create_app(store=store, token="short")


def test_missing_capture_time_is_unknown(store):
    photo = store.save(PhotoInput(**META), sanitize_image(png(), "image/png"))
    assert photo.captured_at is None and photo.captured_date is None
    assert photo.capture_time_source == "unknown"
