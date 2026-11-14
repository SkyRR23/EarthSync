"""Mockable HLS / OPERA RTC-S1 boundaries with explicit unverified access.

No product discovery is presented as a QA-checked field observation. Activating
real retrieval requires provider credentials/access, pixel extraction and review.
"""

from typing import Literal, Protocol

from pydantic import Field, model_validator

from .models import Contract, SatelliteRecord, TimelineQuery


class ProviderResult(Contract):
    provider: str
    status: Literal["available", "no_observations", "unavailable"]
    reason: str
    source_url: str = Field(pattern=r"^https://")
    records: list[SatelliteRecord] = Field(default_factory=list, max_length=1000)
    limitations: list[str] = Field(min_length=1)

    @model_validator(mode="after")
    def status_matches(self):
        if bool(self.records) != (self.status == "available"):
            raise ValueError("Only available results may contain observations")
        return self


class SatelliteAdapter(Protocol):
    provider: str
    modality: Literal["optical", "radar"]
    source_url: str

    async def observe(self, query: TimelineQuery) -> ProviderResult: ...


class HlsAdapter:
    provider = "NASA HLS"
    modality = "optical"
    source_url = "https://hls.gsfc.nasa.gov/data/"

    async def observe(self, query: TimelineQuery) -> ProviderResult:
        return ProviderResult(
            provider=self.provider,
            status="unavailable",
            reason="access_unverified",
            source_url=self.source_url,
            limitations=[
                "HLS documentation/CMR access was proxy-blocked on 2026-11-14; "
                "Earthdata authorization and field pixels were not verified.",
                "HLS L30/S30 acquisition coverage, Fmask QA, scaling and valid "
                "red/NIR pixels must be checked before deriving point NDVI.",
                "No optical measurements, field-health or disease inference available.",
            ],
        )


class RtcS1Adapter:
    provider = "NASA OPERA RTC-S1"
    modality = "radar"
    source_url = "https://www.jpl.nasa.gov/go/opera/opera-products/rtc-product/"

    async def observe(self, query: TimelineQuery) -> ProviderResult:
        return ProviderResult(
            provider=self.provider,
            status="unavailable",
            reason="access_unverified",
            source_url=self.source_url,
            limitations=[
                "ASF/product documentation access was proxy-blocked on 2026-11-14; "
                "actual RTC-S1 access and geographic coverage were not verified.",
                "Acquisition time, product version, gamma0 convention/units, "
                "polarization, orbit, incidence geometry and native QA must be "
                "verified before returning radar point samples.",
                "Radar brightness is not a validated soil-moisture, flood or disease estimate.",
            ],
        )
