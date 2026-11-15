"""Appearance observations and lab transcription are intentionally separate."""

import re
import shutil
import subprocess
from datetime import date
from typing import Literal, Protocol

from pydantic import BaseModel, ConfigDict, Field, model_validator

from .storage import ResearchError

PHOTO_LIMITATIONS = [
    "A photograph cannot measure pH, N, P, K, salinity, CEC, organic carbon, moisture percentage or laboratory texture.",
    "Lighting, scale, occlusion and camera processing limit visible observations.",
    "Appearance does not establish crop suitability or a treatment requirement.",
]
FEATURES = Literal[
    "surface_cracking",
    "possible_crusting",
    "standing_water",
    "possible_erosion",
    "dark_appearance",
    "light_appearance",
    "visible_organic_debris",
    "exposed_roots",
]


class StrictModel(BaseModel):
    model_config = ConfigDict(
        extra="forbid", allow_inf_nan=False, str_strip_whitespace=True
    )


class AppearanceObservation(StrictModel):
    feature: FEATURES
    visibility: Literal["visible", "uncertain"]


class AppearanceOutput(StrictModel):
    observations: list[AppearanceObservation] = Field(max_length=8)
    inconclusive: bool

    @model_validator(mode="after")
    def empty_is_inconclusive(self):
        if not self.observations and not self.inconclusive:
            raise ValueError("An empty observation cannot be conclusive")
        return self


class VisionProvider(Protocol):
    """An operator-supplied adapter must document the actual vision-capable model."""

    name: str
    model: str
    supports_images: bool
    external: bool

    def describe(self, sanitized_png: bytes) -> dict: ...


def analyze_photo(photo_id, image, *, provider=None, consent=False):
    result = {
        "photo_id": str(photo_id),
        "status": "unavailable",
        "observations": [],
        "inconclusive": True,
        "chemical_measurements_available": False,
        "measurements": [],
        "human_confirmed": False,
        "limitations": PHOTO_LIMITATIONS,
        "next_step": "Record dated field observations or obtain a representative laboratory test with method and depth.",
        "provider": None,
        "model": None,
    }
    if (
        provider is None
        or not provider.supports_images
        or not provider.name
        or not provider.model
    ):
        return result
    if provider.external and not consent:
        raise ResearchError("EXTERNAL_IMAGE_CONSENT_REQUIRED", 422)
    try:
        output = AppearanceOutput.model_validate(provider.describe(image))
    except Exception:
        # Provider failures and rejected outputs never leak provider payloads or private pixels.
        return {**result, "status": "provider_failed_or_invalid"}
    return {
        **result,
        **output.model_dump(),
        "status": "unverified_model_observation",
        "provider": provider.name,
        "model": provider.model,
    }


class LabValue(StrictModel):
    parameter: Literal[
        "ph",
        "organic_matter",
        "nitrogen",
        "phosphorus",
        "potassium",
        "organic_carbon",
        "salinity",
    ]
    value: float = Field(ge=0, le=1_000_000_000)
    unit: str = Field(min_length=1, max_length=60)
    method: str | None = Field(default=None, min_length=1, max_length=150)
    depth: str | None = Field(default=None, min_length=1, max_length=100)
    reference_range: str | None = Field(default=None, max_length=150)
    source_locator: str = Field(min_length=1, max_length=150)

    @model_validator(mode="after")
    def plausible(self):
        if self.parameter == "ph" and (self.value > 14 or self.unit.casefold() != "ph"):
            raise ValueError("pH must use pH units and be within 0..14")
        if self.unit == "%" and self.value > 100:
            raise ValueError("Percentage exceeds 100")
        return self


class LabConfirmation(StrictModel):
    confirmed: Literal[True]
    document_kind: Literal["laboratory_report"]
    laboratory: str | None = Field(default=None, min_length=1, max_length=150)
    sample_id: str = Field(min_length=1, max_length=100)
    sample_date: date | None = None
    values: list[LabValue] = Field(min_length=1, max_length=30)

    @model_validator(mode="after")
    def unique(self):
        keys = [(v.parameter, v.depth, v.method) for v in self.values]
        if len(keys) != len(set(keys)):
            raise ValueError("Ambiguous duplicate sample measurement")
        if self.sample_date and self.sample_date > date.today():
            raise ValueError("Sample date cannot be in the future")
        return self


LABELS = {
    "ph": "ph",
    "soil ph": "ph",
    "nitrogen": "nitrogen",
    "phosphorus": "phosphorus",
    "potassium": "potassium",
    "organic matter": "organic_matter",
    "organic carbon": "organic_carbon",
    "salinity": "salinity",
}


def parse_lab_text(text):
    """Conservative single-sample, line-based MVP; uncertain tables need manual entry."""
    result = {
        "status": "manual_entry_required",
        "provider": "local-tesseract",
        "confirmation_required": True,
        "values": [],
        "laboratory": None,
        "sample_id": None,
        "sample_date": None,
        "method": None,
        "depth": None,
        "unreadable_fields": [],
        "limitations": [
            "OCR is an unverified transcription, not laboratory authentication.",
            "A reported sample does not establish chemistry throughout a field.",
            "Units and test method are retained; no conversion to crop suitability is performed.",
        ],
        "recommendation_eligible": False,
    }
    lines = text[:100_000].splitlines()
    fields = {
        "laboratory": r"(?:laboratory|lab name)",
        "sample_id": r"sample id",
        "sample_date": r"sample date",
        "method": r"(?:test method|method)",
        "depth": r"(?:sampling depth|depth)",
    }
    ambiguous = False
    for field, pattern in fields.items():
        matches = [
            m.group(1).strip()
            for line in lines
            if (m := re.fullmatch(pattern + r"\s*:\s*(.{1,150})", line.strip(), re.I))
        ]
        if len(matches) == 1:
            result[field] = matches[0]
        elif len(matches) > 1:
            result["unreadable_fields"].append(field + ": multiple samples/values")
            ambiguous = True
    # Multi-column sample/depth headers and home-test calibration are deliberately unsupported.
    if ambiguous or re.search(
        r"test strip|home.?test|colorimetric|sample\s*(?:1\s+sample\s*2|a\s+sample\s*b)",
        text,
        re.I,
    ):
        return {**result, "status": "ambiguous_document", "values": []}
    for number, line in enumerate(lines, 1):
        match = re.fullmatch(
            r"\s*([A-Za-z ]+)\s*[:=]\s*([0-9]+(?:\.[0-9]+)?)\s*(.*?)\s*", line
        )
        if not match or match[1].strip().casefold() not in LABELS:
            continue
        parameter = LABELS[match[1].strip().casefold()]
        unit = match[3].strip()
        if parameter == "ph" and not unit:
            unit = "pH"  # Dimensionless pH, never an inferred concentration unit.
        if not unit:
            result["unreadable_fields"].append(parameter + ": missing units")
            continue
        try:
            value = LabValue(
                parameter=parameter,
                value=float(match[2]),
                unit=unit,
                # An explicitly pH-named method cannot silently describe N/P/K tests.
                method=result["method"]
                if parameter == "ph"
                and re.search(r"\bph\b", result["method"] or "", re.I)
                else None,
                depth=result["depth"],
                source_locator=f"image 1, OCR line {number}",
            )
        except ValueError:
            result["unreadable_fields"].append(parameter + ": implausible extraction")
            continue
        if any(v["parameter"] == parameter for v in result["values"]):
            return {**result, "status": "ambiguous_document", "values": []}
        result["values"].append(value.model_dump())
    for field in ("laboratory", "sample_id", "sample_date", "method", "depth"):
        if result[field] is None:
            result["unreadable_fields"].append(field)
    if not any(v["parameter"] == "ph" for v in result["values"]):
        result["unreadable_fields"].append("ph")
    result["status"] = (
        "pending_confirmation" if result["values"] else "manual_entry_required"
    )
    return result


class LocalOCR:
    def __init__(self):
        self.executable = shutil.which("tesseract")

    def extract(self, image):
        if not self.executable:
            return {**parse_lab_text(""), "status": "ocr_unavailable", "provider": None}
        try:
            process = subprocess.run(
                [self.executable, "stdin", "stdout", "--psm", "6"],
                input=image,
                capture_output=True,
                timeout=20,
                check=True,
            )
            return parse_lab_text(
                process.stdout[:100_000].decode("utf-8", errors="replace")
            )
        except (subprocess.SubprocessError, OSError):
            return {**parse_lab_text(""), "status": "ocr_failed"}


def soil_context(*, modeled=(), farmer_reported=(), laboratory=()):
    return {
        "schema_version": "earthsync.soil-context.v1",
        "modeled_regional_reference": list(modeled),
        "farmer_reported": list(farmer_reported),
        "laboratory_sample_transcriptions": list(laboratory),
        "recommendation_eligible": False,
        "limitations": [
            "Different samples, depths, methods, dates and spatial support cannot be silently combined.",
            "Disagreements are retained. No category overwrites another or updates the regional model.",
            "A user-confirmed report transcription is not independent laboratory authentication.",
        ],
    }
