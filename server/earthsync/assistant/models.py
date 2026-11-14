"""Proposed assistant boundary; deliberately separate from engine/provider models."""

from datetime import date, datetime
from typing import Annotated, Literal
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict, Field, model_validator, field_validator

VERSION = "assistant.v1-proposal"
Identifier = str
Kind = Literal[
    "observed", "modeled", "forecast", "farmer_reported", "synthetic", "unavailable"
]
Topic = Literal[
    "climate",
    "rainfall",
    "temperature",
    "soil",
    "vegetation",
    "radar",
    "photo",
    "farmer_input",
]
Quality = Literal[
    "available",
    "missing",
    "partial",
    "stale",
    "contradictory",
    "unavailable",
    "unverified",
]


class Model(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Point(Model):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class Selection(Model):
    id: str = Field(min_length=1, max_length=100)
    point: Point
    # Boundary is retained, never used to infer pixel/field overlap.
    boundary: list[Point] = Field(default_factory=list, max_length=500)

    @field_validator("boundary")
    @classmethod
    def polygon(cls, value):
        if value and (len(value) < 4 or value[0] != value[-1]):
            raise ValueError("A boundary needs a closed ring of at least four points")
        return value


class Source(Model):
    id: str = Field(min_length=1, max_length=100)
    provider: str = Field(min_length=1, max_length=200)
    title: str = Field(min_length=1, max_length=400)
    url: str | None = Field(default=None, max_length=2000)

    @field_validator("url")
    @classmethod
    def public_link(cls, value):
        if value is not None:
            parsed = urlsplit(value)
            if (
                parsed.scheme != "https"
                or not parsed.hostname
                or parsed.username
                or parsed.password
            ):
                raise ValueError("Provider links must be HTTPS without credentials")
        return value


class Evidence(Model):
    id: str = Field(min_length=1, max_length=100)
    topic: Topic
    metric: str = Field(min_length=1, max_length=100)
    kind: Kind
    quality: Quality
    value: Annotated[float, Field(strict=True)] | str | None = None
    unit: str | None = Field(default=None, max_length=80)
    start_date: date | None = None
    end_date: date | None = None
    retrieved_at: datetime | None = None
    spatial_support: str | None = Field(default=None, max_length=500)
    scope: Literal["regional", "field", "unlocated"]
    location_id: str | None = Field(default=None, max_length=100)
    source_ids: list[str] = Field(default_factory=list, max_length=20)
    limitations: list[str] = Field(default_factory=list, max_length=20)
    calculation: Literal["none", "rust"] = "none"

    @model_validator(mode="after")
    def semantics(self):
        if self.start_date and self.end_date and self.start_date > self.end_date:
            raise ValueError("Evidence dates must be ordered")
        if self.kind == "unavailable" and self.value is not None:
            raise ValueError("Unavailable evidence cannot contain a value")
        if isinstance(self.value, float) and not self.unit:
            raise ValueError("Numeric evidence needs explicit units")
        if isinstance(self.value, str) and len(self.value) > 500:
            raise ValueError("Evidence text is too long")
        if any(len(text) > 500 for text in self.limitations):
            raise ValueError("Limitations are too long")
        return self


class Decision(Model):
    id: str = Field(min_length=1, max_length=100)
    scenario_id: str = Field(min_length=1, max_length=100)
    status: Literal[
        "supported_by_supplied_evidence",
        "conflicts_with_supplied_evidence",
        "insufficient_information",
        "unsuitable",
        "requires_agronomic_validation",
        "supported",
        "conditional",
        "unknown",
    ]
    source_ids: list[str] = Field(default_factory=list, max_length=20)
    evidence_ids: list[str] = Field(default_factory=list, max_length=20)
    limitations: list[str] = Field(default_factory=list, max_length=20)
    synthetic: bool = False


class Context(Model):
    schema_version: Literal["assistant.v1-proposal"] = VERSION
    context_id: str = Field(min_length=1, max_length=100)
    approximate_location: Point | None = None
    selected_area: Selection | None = None
    confirmed_farm: Selection | None = None
    evidence: list[Evidence] = Field(default_factory=list, max_length=120)
    decisions: list[Decision] = Field(default_factory=list, max_length=30)
    sources: list[Source] = Field(default_factory=list, max_length=100)
    limitations: list[str] = Field(default_factory=list, max_length=30)

    @model_validator(mode="after")
    def unique_ids(self):
        for records in (self.evidence, self.decisions, self.sources):
            ids = [record.id for record in records]
            if len(ids) != len(set(ids)):
                raise ValueError("IDs must be unique within each record collection")
        if (
            self.selected_area
            and self.confirmed_farm
            and self.selected_area.id == self.confirmed_farm.id
        ):
            raise ValueError("Regional selection and farm need distinct IDs")
        return self


class ChatRequest(Model):
    schema_version: Literal["assistant.v1-proposal"] = VERSION
    question: str = Field(min_length=1, max_length=1000)
    language: Literal["en", "es"] = "en"
    expanded: bool = False
    context: Context

    @field_validator("question")
    @classmethod
    def nonblank(cls, value):
        if not value.strip():
            raise ValueError("Question cannot be blank")
        return value


class Claim(Model):
    category: Literal[
        "retrieved_fact",
        "deterministic_calculation",
        "general_knowledge",
        "unavailable_evidence",
    ]
    text: str
    evidence_ids: list[str] = Field(default_factory=list)
    source_ids: list[str] = Field(default_factory=list)


class ChatResponse(Model):
    schema_version: Literal["assistant.v1-proposal"] = VERSION
    context_id: str
    language: Literal["en", "es"]
    intent: str
    claims: list[Claim]
    citations: list[Source]
    # Original evidence is kept verbatim in opt-in details, never interpreted as instructions.
    evidence: list[Evidence]
    decisions: list[Decision]
    limitations: list[str]
    warnings: list[str]
    suggested_questions: list[str]
