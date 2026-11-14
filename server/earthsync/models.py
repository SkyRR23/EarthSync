from calendar import monthrange
from datetime import date, datetime, timezone
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Model(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class SeasonQuery(Model):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    start_year: int = Field(ge=1981, le=9998)
    start_month: int = Field(ge=1, le=12)
    end_year: int = Field(ge=1981, le=9998)
    end_month: int = Field(ge=1, le=12)

    @model_validator(mode="after")
    def window(self):
        span = (
            (self.end_year - self.start_year) * 12 + self.end_month - self.start_month
        )
        if not 0 <= span < 24:
            raise ValueError("Require an ordered inclusive window of at most 24 months")
        if self.end >= datetime.now(timezone.utc).date().replace(day=1):
            raise ValueError("Only finished calendar months are supported")
        return self

    @property
    def start(self):
        return date(self.start_year, self.start_month, 1)

    @property
    def end(self):
        return date(
            self.end_year, self.end_month, monthrange(self.end_year, self.end_month)[1]
        )

    def months(self):
        for index in range(
            self.start_year * 12 + self.start_month - 1,
            self.end_year * 12 + self.end_month,
        ):
            yield index // 12, index % 12 + 1


class YearMonth(Model):
    year: int = Field(ge=1, le=9999)
    month: int = Field(ge=1, le=12)


class Window(Model):
    start: YearMonth
    end: YearMonth


class Metadata(Model):
    source: str = "NASA POWER"
    dataset: str = "POWER daily meteorology / MERRA-2"
    data_kind: Literal["modeled"] = "modeled"
    rainfall_unit: Literal["mm"] = "mm"
    temperature_unit: Literal["deg_c"] = "deg_c"


class Observation(Model):
    period: YearMonth
    rainfall_mm: float | None
    mean_temperature_c: float | None
    rainfall_complete: bool
    temperature_complete: bool


class SeasonalRequest(Model):
    window: Window
    metadata: Metadata = Field(default_factory=Metadata)
    observations: list[Observation]


class Environment(Model):
    latitude: float
    longitude: float
    seasonal: SeasonalRequest


class SeasonResponse(Model):
    schema_version: Literal["1.0-proposal"] = "1.0-proposal"
    status: Literal["success"] = "success"
    environment: Environment
    provenance: dict
    cache: dict
