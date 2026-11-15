import io

import pytest
from PIL import Image, ImageDraw, ImageFont
from pydantic import ValidationError

from earthsync.evidence.images import sanitize_image, InvalidImage
from earthsync.research.api import PREFIX
from earthsync.research.soil import (
    LabConfirmation,
    LabValue,
    LocalOCR,
    analyze_photo,
    parse_lab_text,
)
from earthsync.research.storage import ResearchError

TEXT = """SYNTHETIC SOFTWARE TEST - NOT A REAL LAB REPORT
Laboratory: Example Test Laboratory
Sample ID: TEST-1
Sample date: 2026-01-15
Test method: pH in water
Sampling depth: 0-15 cm
pH: 6.4
Phosphorus: 12 mg/kg
Potassium: 80 mg/kg
"""


def confirmation():
    return {
        "confirmed": True,
        "document_kind": "laboratory_report",
        "laboratory": "Example Test Laboratory",
        "sample_id": "TEST-1",
        "sample_date": "2026-01-15",
        "values": parse_lab_text(TEXT)["values"],
    }


def test_parse_exact_values_units_method_depth():
    result = parse_lab_text(TEXT)
    assert result["confirmation_required"] is True
    assert result["status"] == "pending_confirmation"
    assert result["values"][0]["value"] == 6.4
    assert result["values"][0]["unit"] == "pH"
    assert result["values"][1]["unit"] == "mg/kg"
    assert result["values"][0]["method"] == "pH in water"
    assert result["values"][0]["depth"] == "0-15 cm"
    assert result["recommendation_eligible"] is False


@pytest.mark.parametrize(
    "text,status",
    [
        ("", "manual_entry_required"),
        ("Nitrogen: 12", "manual_entry_required"),
        ("pH: 99", "manual_entry_required"),
        ("Sample ID: A\nSample ID: B\npH: 6.5", "ambiguous_document"),
        ("Depth: 0-5 cm\nDepth: 5-15 cm\npH: 6.5", "ambiguous_document"),
        ("pH: 6.5\npH: 7.2", "ambiguous_document"),
        ("Home test strip pH: 7", "ambiguous_document"),
    ],
)
def test_unreadable_missing_and_multiple_samples(text, status):
    result = parse_lab_text(text)
    assert result["status"] == status
    assert result["values"] == []
    assert result["confirmation_required"]


def test_missing_ph_does_not_get_filled():
    result = parse_lab_text("Sample ID: A\nNitrogen: 1 mg/kg")
    assert "ph" in result["unreadable_fields"]
    assert all(v["parameter"] != "ph" for v in result["values"])


@pytest.mark.parametrize(
    "kwargs",
    [
        {"parameter": "ph", "value": 15, "unit": "pH"},
        {"parameter": "ph", "value": 7, "unit": "mg/kg"},
        {"parameter": "nitrogen", "value": 2, "unit": ""},
        {"parameter": "organic_matter", "value": 101, "unit": "%"},
        {"parameter": "nitrogen", "value": float("nan"), "unit": "mg/kg"},
    ],
)
def test_implausible_values_rejected(kwargs):
    with pytest.raises(ValidationError):
        LabValue(**kwargs, source_locator="image 1")


def test_correction_requires_actual_confirmation():
    raw = confirmation()
    raw["confirmed"] = False
    with pytest.raises(ValidationError):
        LabConfirmation.model_validate(raw)
    raw["confirmed"] = True
    raw["values"][0]["value"] = 6.6
    assert LabConfirmation.model_validate(raw).values[0].value == 6.6


def test_lab_original_and_confirmation_stay_separate(
    research_client, credential, png, monkeypatch
):
    monkeypatch.setattr(LocalOCR, "extract", lambda _, image: parse_lab_text(TEXT))
    farm = credential["farm_ids"][0]
    photo = research_client.post(
        PREFIX + "/photos",
        params={"farm_id": farm},
        content=png,
        headers={"content-type": "image/png"},
    ).json()
    report = research_client.post(
        PREFIX + "/lab-reports/extract", json={"farm_id": farm, "photo_id": photo["id"]}
    ).json()
    assert report["confirmed"] is None
    value = confirmation()
    value["values"][0]["value"] = 6.6
    response = research_client.post(
        PREFIX + f"/lab-reports/{report['id']}/confirm",
        params={"farm_id": farm},
        json=value,
    )
    assert response.status_code == 200
    result = response.json()
    assert result["confirmed"]["values"][0]["value"] == 6.6
    assert result["original"]["values"][0]["value"] == 6.4
    assert result["confirmed"]["laboratory_authenticity_verified"] is False
    context = research_client.post(
        PREFIX + "/soil/context",
        json={
            "farm_id": farm,
            "report_ids": [report["id"]],
            "farmer_reports": ["Waterlogged yesterday"],
        },
    ).json()
    assert len(context["laboratory_sample_transcriptions"]) == 1
    assert context["farmer_reported"] == ["Waterlogged yesterday"]
    assert context["modeled_regional_reference"] == []
    assert context["recommendation_eligible"] is False


def test_cross_farm_report_confirmation(
    research_client, research_store, credential, png, monkeypatch
):
    import time

    monkeypatch.setattr(LocalOCR, "extract", lambda _, image: parse_lab_text(TEXT))
    farm = credential["farm_ids"][0]
    photo = research_client.post(
        PREFIX + "/photos",
        params={"farm_id": farm},
        content=png,
        headers={"content-type": "image/png"},
    ).json()
    report = research_client.post(
        PREFIX + "/lab-reports/extract", json={"farm_id": farm, "photo_id": photo["id"]}
    ).json()
    other = research_store.provision(
        "other",
        "bob",
        ["lab:confirm", "lab:extract", "soil:reference:read"],
        time.time() + 60,
    )
    research_client.headers["authorization"] = "Bearer " + other["token"]
    for farm_id in [farm, other["farm_ids"][0]]:
        assert (
            research_client.post(
                PREFIX + f"/lab-reports/{report['id']}/confirm",
                params={"farm_id": farm_id},
                json=confirmation(),
            ).status_code
            == 404
        )


class FakeVision:
    name, model, supports_images, external = "mock", "mock-vision", True, True

    def describe(self, image):
        return {
            "observations": [{"feature": "surface_cracking", "visibility": "visible"}],
            "inconclusive": False,
        }


def test_vision_consent_and_allowlisted_structured_output(png):
    with pytest.raises(ResearchError, match="CONSENT"):
        analyze_photo("test", png, provider=FakeVision())
    result = analyze_photo("test", png, provider=FakeVision(), consent=True)
    assert result["status"] == "unverified_model_observation"
    assert result["measurements"] == [] and result["human_confirmed"] is False

    class TextOnly(FakeVision):
        supports_images = False

    assert (
        analyze_photo("test", png, provider=TextOnly(), consent=True)["status"]
        == "unavailable"
    )


@pytest.mark.parametrize(
    "payload",
    [
        {"ph": 6.5},
        {
            "observations": [
                {"feature": "nitrogen_deficiency", "visibility": "visible"}
            ],
            "inconclusive": False,
        },
        {"observations": [], "inconclusive": True, "recommendation_eligible": True},
        {
            "observations": [
                {
                    "feature": "surface_cracking",
                    "visibility": "visible",
                    "confidence": 0.99,
                }
            ],
            "inconclusive": False,
        },
    ],
)
def test_invalid_vision_cannot_invent_measurements(payload, png):
    class BadVision(FakeVision):
        def describe(self, image):
            return payload

    result = analyze_photo("test", png, provider=BadVision(), consent=True)
    assert result["status"] == "provider_failed_or_invalid"
    assert result["measurements"] == []


def test_ocr_failure_and_unavailable(png, monkeypatch):
    ocr = LocalOCR()
    ocr.executable = None
    assert ocr.extract(png)["status"] == "ocr_unavailable"
    ocr.executable = "/nonexistent/test-tesseract"
    assert ocr.extract(png)["status"] == "ocr_failed"


def test_real_local_ocr_on_labeled_synthetic_report(tmp_path):
    ocr = LocalOCR()
    if not ocr.executable:
        pytest.skip("Optional local Tesseract is not installed")
    image = Image.new("RGB", (1600, 750), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("DejaVuSans.ttf", 30)
    draw.multiline_text((35, 30), TEXT, font=font, fill="black", spacing=12)
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    result = ocr.extract(stream.getvalue())
    assert result["status"] == "pending_confirmation"
    assert next(v for v in result["values"] if v["parameter"] == "ph")["value"] == 6.4
    assert result["sample_id"] == "TEST-1"
    assert result["confirmation_required"]


def test_dimension_and_pixel_bomb_limits():
    stream = io.BytesIO()
    Image.new("RGB", (4100, 4100)).save(stream, format="PNG")
    with pytest.raises(InvalidImage):
        sanitize_image(stream.getvalue(), "image/png")
