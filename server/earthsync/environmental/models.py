"""Additive environmental-context/1.0-proposal contract.

Provider estimates stay regional even when associated with a confirmed farm.
There are deliberately no diagnoses, crop scores or confidence percentages.
"""

from datetime import datetime
from typing import Annotated, Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StrictBool,
    model_validator,
)


class Model(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Point(Model):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class Area(Model):
    kind: Literal["selected_area"]
    representative_point: Point
    # WGS84 west,south,east,north; west > east denotes the antimeridian.
    bbox: tuple[float, float, float, float] | None = None

    @model_validator(mode="after")
    def bounds(self):
        if self.bbox is not None:
            west, south, east, north = self.bbox
            p = self.representative_point
            inside_lon = (
                west <= p.longitude <= east
                if west <= east
                else p.longitude >= west or p.longitude <= east
            )
            if not (
                -180 <= west <= 180
                and -180 <= east <= 180
                and -90 <= south < north <= 90
                and south <= p.latitude <= north
                and inside_lon
            ):
                raise ValueError("Representative point must be inside a valid bbox")
        return self


class Farm(Model):
    kind: Literal["confirmed_farm"]
    field_id: str = Field(min_length=1, max_length=128)
    farmer_confirmed: StrictBool
    point: Point

    @model_validator(mode="after")
    def confirmed(self):
        if not self.farmer_confirmed:
            raise ValueError("A farm query requires farmer confirmation")
        return self


Depth = Literal["0-5cm", "5-15cm", "15-30cm", "30-60cm", "60-100cm", "100-200cm"]


class ContextQuery(Model):
    schema_version: Literal["environmental-context/1.0-proposal"]
    target: Annotated[Area | Farm, Field(discriminator="kind")]
    approximate_user_location: Point | None = None
    timezone: str = Field(default="UTC", max_length=64)
    soil_depths: list[Depth] = Field(default=["0-5cm"], min_length=1, max_length=6)

    @model_validator(mode="after")
    def valid_options(self):
        try:
            ZoneInfo(self.timezone)
        except (ZoneInfoNotFoundError, ValueError) as exc:
            raise ValueError("Use an IANA timezone") from exc
        if len(set(self.soil_depths)) != len(self.soil_depths):
            raise ValueError("Duplicate soil depths")
        return self

    @property
    def point(self):
        if isinstance(self.target, Farm):
            return self.target.point
        return self.target.representative_point


class Source(Model):
    provider: str
    dataset: str
    api_version: str | None = None
    release: str | None = None
    model: str | None = None
    model_identity_basis: str | None = None
    documentation: list[str]
    license: str
    attribution: str


class Retrieval(Model):
    requested_at: AwareDatetime
    retrieved_at: AwareDatetime | None = None
    endpoint: str
    query: dict
    http_status: int | None = None
    response_sha256: str | None = None
    etag: str | None = None
    last_modified: str | None = None
    # No raw body retention in this service; hashes are not raw-file references.
    raw_reference: str | None = None


class SpatialSupport(Model):
    query_point: Point
    returned_point: Point | None = None
    crs: Literal["EPSG:4326"] = "EPSG:4326"
    method: str
    nominal_resolution_m: float | None = None
    native_footprint: dict | None = None
    scope: Literal["regional_context"] = "regional_context"
    on_farm_measurement: Literal[False] = False


class TemporalSupport(Model):
    kind: Literal["static_model", "weather", "satellite_composite"]
    timezone: str | None = None
    utc_offset_seconds: int | None = None
    current_interval_seconds: int | None = None
    issue_time: datetime | None = None
    valid_start: datetime | None = None
    valid_end: datetime | None = None
    retrieved_at: datetime | None = None
    expires_at: datetime | None = None
    freshness_policy: str | None = None
    freshness: Literal["not_applicable", "unknown", "fresh", "stale"] = "unknown"


class Value(Model):
    variable: str
    data_kind: Literal[
        "observed", "modeled", "forecast", "farmer_reported", "synthetic"
    ]
    depth_cm: tuple[int, int] | None = None
    statistic: str
    start: datetime | None = None
    end: datetime | None = None
    original_value: float | None = None
    original_unit: str | None = None
    value: float | None = None
    unit: str
    scale: float
    offset: float = 0
    quality: Literal["present", "missing", "rejected"]
    reason: str | None = None
    usable_for_analysis: Literal[False] = False

    @model_validator(mode="after")
    def missing_is_null(self):
        if self.quality != "present" and self.value is not None:
            raise ValueError("Missing or rejected values must be null")
        if self.quality == "present" and (
            self.value is None or self.original_value is None
        ):
            raise ValueError("Present values require original and converted values")
        return self


class Quality(Model):
    expected: int = Field(ge=0)
    present: int = Field(ge=0)
    missing: int = Field(ge=0)
    rejected: int = Field(ge=0)
    qa_status: Literal["not_applicable", "missing", "unverified"]
    uncertainty_status: Literal["provider_quantiles", "not_supplied"] = "not_supplied"
    reasons: list[str]


class Evidence(Model):
    schema_version: Literal["environmental-evidence/1.0-proposal"] = (
        "environmental-evidence/1.0-proposal"
    )
    context_kind: Literal["soil", "weather", "ndvi", "evi", "land_surface_temperature"]
    availability: Literal["reference_only", "partial", "unavailable"]
    reason: str | None = None
    source: Source
    retrieval: Retrieval | None = None
    spatial_support: SpatialSupport
    temporal_support: TemporalSupport
    values: list[Value] = Field(default_factory=list)
    quality: Quality
    limitations: list[str]
    cache_hit: bool = False


class Situation(Model):
    availability: dict[str, str]
    present_value_counts: dict[str, int]
    field_specific_evidence: Literal["not_supplied"] = "not_supplied"
    agricultural_diagnosis: None = None
    drainage: None = None
    crop_recommendations: None = None


class ContextResponse(Model):
    schema_version: Literal["environmental-context/1.0-proposal"] = (
        "environmental-context/1.0-proposal"
    )
    as_of: datetime
    query: ContextQuery
    evidence: list[Evidence]
    situation: Situation
