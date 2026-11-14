"""Provisional evidence.v1 contract. No image-to-location inference."""

from datetime import date, datetime
from typing import Literal

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    model_validator,
)


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Position(Contract):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    uncertainty_m: float | None = Field(default=None, ge=0)


class PhotoPosition(Position):
    source: Literal["consented_exif", "farmer_reported"]
    # This consent authorizes retention of coordinates, never original metadata.
    retention_authorized: Literal[True]


class FarmAssociation(Contract):
    farm_id: str = Field(min_length=1, max_length=128, pattern=r"^\S(?:.*\S)?$")
    confirmed_by_farmer: Literal[True]


class ConfirmedField(FarmAssociation):
    point: Position


class PhotoInput(Contract):
    schema_version: Literal["evidence.v1"] = "evidence.v1"
    source: Literal["camera", "gallery", "browser_file"]
    data_kind: Literal["farmer_supplied", "synthetic"] = "farmer_supplied"
    category: Literal["crop", "soil", "water"]
    caption: str = Field(default="", max_length=1000)
    farmer_observations: str = Field(default="", max_length=2000)
    captured_at: AwareDatetime | None = None
    captured_date: date | None = None
    capture_time_source: Literal["farmer_reported", "unknown"] = "unknown"
    farm: FarmAssociation | None = None
    position: PhotoPosition | None = None

    @model_validator(mode="after")
    def capture_consistency(self):
        if self.captured_at and self.captured_date:
            raise ValueError("Use a timestamp or a date, not both")
        known = self.captured_at is not None or self.captured_date is not None
        if known != (self.capture_time_source == "farmer_reported"):
            raise ValueError("Capture date/time needs an explicit farmer report")
        return self


class Photo(PhotoInput):
    id: str
    uploaded_at: AwareDatetime
    updated_at: AwareDatetime
    mime_type: Literal["image/png"] = "image/png"
    width_px: int
    height_px: int
    size_bytes: int
    sha256: str
    metadata_stripped: Literal[True] = True
    evidence_kind: Literal["farmer_supplied_photo"] = "farmer_supplied_photo"
    spatial_support: Literal["photo_view_extent_unknown"] = "photo_view_extent_unknown"
    quality: Literal["not_scientifically_validated"] = "not_scientifically_validated"


class TimelineQuery(Contract):
    schema_version: Literal["evidence.v1"] = "evidence.v1"
    field: ConfirmedField
    start: date
    end: date

    @model_validator(mode="after")
    def ordered(self):
        if self.end < self.start or (self.end - self.start).days > 366:
            raise ValueError("Use an ordered interval of at most 366 days")
        return self


class SatelliteRecord(Contract):
    """A provider-normalized point sample, not a claim of whole-field coverage.

    Adapters must inspect native QA/pixels before supplying usable records.
    Asset discovery or footprint intersection alone cannot produce this record.
    """

    id: str = Field(min_length=1, max_length=256)
    modality: Literal["optical", "radar"]
    evidence_kind: Literal["observed", "synthetic"]
    source_url: str = Field(pattern=r"^https://", max_length=2048)
    product: str = Field(min_length=1, max_length=128)
    product_version: str = Field(min_length=1, max_length=64)
    acquired_at: AwareDatetime
    retrieved_at: AwareDatetime
    field: ConfirmedField
    spatial_support: Literal["confirmed_point_pixel"]
    pixel_bbox: tuple[float, float, float, float]
    resolution_m: float = Field(gt=0)
    pixel_count: int = Field(ge=1)
    valid_pixel_count: int = Field(ge=0)
    qa: Literal["usable", "limited", "rejected", "unknown"]
    qa_method: str = Field(min_length=1, max_length=1000)
    limitations: list[str] = Field(min_length=1, max_length=50)
    metric: Literal["ndvi", "gamma0_backscatter"]
    value: float | None
    units: Literal["1", "dB"]
    # Geometry keys are provider-normalized; unknown geometry is not comparable.
    platform: str = Field(min_length=1, max_length=64)
    geometry_id: str | None = Field(default=None, min_length=1, max_length=256)
    relative_orbit: int | None = Field(default=None, ge=1)
    orbit_direction: Literal["ascending", "descending"] | None = None
    polarization: Literal["VV", "VH", "HH", "HV"] | None = None
    incidence_angle_deg: float | None = Field(default=None, ge=0, le=90)

    @model_validator(mode="after")
    def consistent(self):
        if self.retrieved_at < self.acquired_at:
            raise ValueError("An observation must be acquired before retrieval")
        west, south, east, north = self.pixel_bbox
        if not (-180 <= west < east <= 180 and -90 <= south < north <= 90):
            raise ValueError("Require a non-wrapping WGS84 pixel footprint")
        if self.valid_pixel_count > self.pixel_count:
            raise ValueError("Invalid pixel coverage")
        if self.qa == "usable" and (
            self.value is None or self.valid_pixel_count != self.pixel_count
        ):
            raise ValueError("Usable samples require complete valid pixels and a value")
        if self.modality == "optical":
            if self.metric != "ndvi" or self.units != "1":
                raise ValueError("Optical v1 supports only dimensionless NDVI")
            if self.value is not None and not -1 <= self.value <= 1:
                raise ValueError("Invalid NDVI")
        elif self.metric != "gamma0_backscatter" or self.units != "dB":
            raise ValueError("Radar v1 requires explicitly normalized gamma0 dB")
        if self.value is not None and self.valid_pixel_count == 0:
            raise ValueError("No value without valid pixels")
        return self


def capture_day(photo: Photo) -> date | None:
    return photo.captured_date or (
        photo.captured_at.date() if isinstance(photo.captured_at, datetime) else None
    )
