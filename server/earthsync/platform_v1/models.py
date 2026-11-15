"""Versioned evidence sidecars. Native units/support survive engine projection."""

from datetime import date
from datetime import date as CalendarDate
from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator
from shapely.geometry import Point as GeoPoint
from shapely.geometry import shape

VERSION = "earthsync.evidence.v1.0"
ENGINE_VERSION = "earthsync.engine.v0.3.0"


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Point(Contract):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class Polygon(Contract):
    type: Literal["Polygon"] = "Polygon"
    coordinates: list[list[tuple[float, float]]] = Field(min_length=1, max_length=1)

    @model_validator(mode="after")
    def valid(self):
        ring = self.coordinates[0]
        if not 4 <= len(ring) <= 1000 or ring[0] != ring[-1]:
            raise ValueError("Require a closed exterior ring of 4..1000 vertices")
        if any(not (-180 <= x <= 180 and -90 <= y <= 90) for x, y in ring):
            raise ValueError("Coordinates must be EPSG:4326 longitude/latitude")
        geom = shape(self.model_dump())
        if not geom.is_valid or geom.area <= 0 or geom.bounds[2] - geom.bounds[0] > 180:
            raise ValueError("Invalid, degenerate or antimeridian-crossing polygon")
        return self


class FarmInput(Contract):
    name: str = Field(min_length=1, max_length=100)
    confirmed_point: Point
    confirmed_polygon: Polygon | None = None
    confirmed_on: date
    production_system: Literal["dryland", "rainfed", "irrigated", "flooded_lowland"]

    @model_validator(mode="after")
    def association(self):
        if self.confirmed_polygon and not shape(
            self.confirmed_polygon.model_dump()
        ).covers(
            GeoPoint(self.confirmed_point.longitude, self.confirmed_point.latitude)
        ):
            raise ValueError("Confirmed farm point must lie within confirmed polygon")
        if self.confirmed_on > date.today():
            raise ValueError("Confirmation cannot be in the future")
        return self


class Farm(FarmInput):
    id: UUID


class FarmLinkInput(Contract):
    local_profile_id: str = Field(
        min_length=1, max_length=100, pattern=r"^[A-Za-z0-9_-]+$"
    )
    revision: AwareDatetime
    farm: FarmInput


class Spatial(Contract):
    crs: Literal["EPSG:4326"] = "EPSG:4326"
    original_crs: str = Field(default="EPSG:4326", max_length=3000)
    role: Literal[
        "approximate_area",
        "confirmed_farm_point",
        "confirmed_farm_polygon",
        "farm_photo",
        "satellite_acquisition",
        "regional_context",
    ]
    query_point: Point | None = None
    original_geometry: dict | None = None
    support: str = Field(min_length=1, max_length=2000)
    resolution_m: float | None = Field(default=None, gt=0)
    resolution_degrees: tuple[float, float] | None = None
    farm_id: UUID | None = None


class Temporal(Contract):
    start: date | None = None
    end: date | None = None
    observed_at: AwareDatetime | None = None
    acquired_at: AwareDatetime | None = None
    retrieved_at: AwareDatetime
    issued_at: AwareDatetime | None = None
    day_basis: str | None = Field(default=None, max_length=100)
    unknown_reason: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def ordered(self):
        if (self.start is None) != (self.end is None):
            raise ValueError("Both period bounds required")
        if self.start and self.start > self.end:
            raise ValueError("Reversed period")
        if self.issued_at and self.issued_at > self.retrieved_at:
            raise ValueError("Issue time cannot follow retrieval")
        if (
            not any((self.start, self.observed_at, self.acquired_at))
            and not self.unknown_reason
        ):
            raise ValueError("Unknown observation time needs a reason")
        return self


class Depth(Contract):
    top_cm: float = Field(ge=0)
    bottom_cm: float = Field(gt=0)

    @model_validator(mode="after")
    def ordered(self):
        if self.bottom_cm <= self.top_cm:
            raise ValueError("Depth interval must have positive thickness")
        return self


class Measurement(Contract):
    variable: str = Field(min_length=1, max_length=80)
    date: CalendarDate | None = None
    original_value: float | None
    original_unit: str = Field(min_length=1, max_length=80)
    value: float | None
    unit: str = Field(min_length=1, max_length=80)
    conversion: str = Field(min_length=1, max_length=500)
    depth: Depth | None = None
    statistic: str = Field(default="daily", max_length=80)
    quality: Literal["usable", "missing", "suspect", "unavailable"]
    missing_reason: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def missing(self):
        if (self.value is None) != (self.quality in ("missing", "unavailable")):
            raise ValueError("Missing/unavailable quality requires a null value")
        if self.value is None and not self.missing_reason:
            raise ValueError("Missing values need a reason")
        return self


class Evidence(Contract):
    schema_version: Literal["earthsync.evidence.v1.0"] = VERSION
    id: str = Field(pattern=r"^ev_[a-f0-9]{64}$")
    provider: str = Field(min_length=1, max_length=200)
    dataset: str = Field(min_length=1, max_length=200)
    dataset_version: str = Field(min_length=1, max_length=100)
    source_url: str = Field(min_length=1, max_length=2000)
    source_identifier: str = Field(min_length=1, max_length=500)
    data_type: Literal[
        "observed", "modeled", "forecast", "farmer_reported", "reference", "synthetic"
    ]
    spatial: Spatial
    temporal: Temporal
    measurements: list[Measurement] = Field(max_length=5000)
    quality_flags: list[str] = Field(max_length=100)
    missing_reasons: list[str] = Field(max_length=100)
    limitations: list[str] = Field(min_length=1, max_length=100)
    usable_for_assessment: bool = False
    review: Literal["unreviewed", "reference_only", "reviewed", "synthetic"]
    response_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    source_metadata: dict

    @model_validator(mode="after")
    def eligibility(self):
        if self.usable_for_assessment and (
            self.data_type in ("reference", "synthetic")
            or self.review != "reviewed"
            or not self.measurements
        ):
            raise ValueError(
                "Assessment evidence needs reviewed, nonsynthetic measurements"
            )
        if self.data_type == "forecast" and not self.temporal.issued_at:
            if self.usable_for_assessment:
                raise ValueError("Usable forecasts need a verified issue time")
        if self.temporal.start:
            if any(
                m.date and not self.temporal.start <= m.date <= self.temporal.end
                for m in self.measurements
            ):
                raise ValueError("Measurement date outside source period")
        return self


class ClimateQuery(Contract):
    point: Point
    start: date
    end: date
    lineage: Literal["MERRA2"] = "MERRA2"
    contract_version: Literal["power-daily-merra2.v1"] = "power-daily-merra2.v1"

    @model_validator(mode="after")
    def period(self):
        if self.start.year < 1981 or not 0 <= (self.end - self.start).days < 366:
            raise ValueError("Require 1..366 ordered historical days from 1981")
        if self.end >= date.today():
            raise ValueError("Daily climate is historical, not a forecast")
        return self


class PlanSelection(Contract):
    reference_region: str | None = Field(default=None, max_length=150)
    profile_id: str = Field(min_length=1, max_length=150)
    start: CalendarDate
    end: CalendarDate

    @model_validator(mode="after")
    def period(self):
        if self.start > self.end:
            raise ValueError("Reversed plan period")
        return self


class AssessmentInput(Contract):
    catalog_version: Literal["v1", "v2"] = "v1"
    farmer_report_ids: list[UUID] = Field(default_factory=list, max_length=20)
    environmental_job_ids: list[UUID] = Field(default_factory=list, max_length=10)
    observation_ids: list[UUID] = Field(default_factory=list, max_length=20)
    farm_id: UUID
    evidence_ids: list[str] = Field(default_factory=list, max_length=50)
    profile_ids: list[str] = Field(default_factory=list, max_length=20)
    plans: list[PlanSelection] = Field(default_factory=list, max_length=20)
    sequential_field: bool = False
    pilot_id: str | None = Field(default=None, max_length=100)
    start: date
    end: date

    @model_validator(mode="after")
    def period(self):
        if not 0 <= (self.end - self.start).days < 366:
            raise ValueError("Require 1..366 ordered assessment days")
        if len(set(self.environmental_job_ids)) != len(
            self.environmental_job_ids
        ) or len(set(self.observation_ids)) != len(self.observation_ids):
            raise ValueError("Duplicate reference snapshots/reports")
        if len(set(self.farmer_report_ids)) != len(self.farmer_report_ids):
            raise ValueError("Duplicate farmer reports")
        if self.plans and self.profile_ids:
            raise ValueError("Choose alternatives or an explicit sequence")
        if len(self.plans) > 1 and not self.sequential_field:
            raise ValueError(
                "Multiple sequence plans require explicit sequential-field assertion"
            )
        if any(p.start < self.start or p.end > self.end for p in self.plans):
            raise ValueError("Plan outside assessment period")
        if len(set(self.evidence_ids)) != len(self.evidence_ids) or len(
            set(self.profile_ids)
        ) != len(self.profile_ids):
            raise ValueError("Duplicate evidence or profile IDs")
        return self


class HistoryInput(Contract):
    crop_id: str | None = Field(
        default=None, pattern=r"^[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+$", max_length=150
    )
    fallow: bool = False
    start: CalendarDate
    end: CalendarDate

    @model_validator(mode="after")
    def period(self):
        if self.start > self.end or self.end > CalendarDate.today():
            raise ValueError("History requires an ordered historical period")
        if self.fallow and self.crop_id is not None:
            raise ValueError("Fallow is distinct from a crop")
        return self


class ObservationInput(Contract):
    """Farmer reports; never independently verified crop or soil evidence."""

    observed_on: CalendarDate
    crop_name: str | None = Field(default=None, min_length=1, max_length=150)
    planting_on: CalendarDate | None = None
    growth_stage: Literal[
        "unknown",
        "establishment",
        "vegetative",
        "flowering",
        "fruiting",
        "maturing",
        "harvested",
    ] = "unknown"
    irrigation: Literal["unknown", "none", "rain_only", "supplemental", "regular"] = (
        "unknown"
    )
    drainage: Literal[
        "unknown",
        "standing_water_reported",
        "drains_freely_reported",
        "poor_drainage_reported",
    ] = "unknown"
    notes: str = Field(min_length=1, max_length=2000)

    @model_validator(mode="after")
    def dates(self):
        if self.observed_on > CalendarDate.today() or (
            self.planting_on and self.planting_on > self.observed_on
        ):
            raise ValueError(
                "Report dates must be historical; planting cannot follow observation"
            )
        return self
