"""SoilGrids v2 REST capture reader and opt-in transport probe.

The provider currently documents this endpoint as paused. The default adapter
returns unavailable. Probe mode is for fresh verification, not production use.
No WMS display pixel is misrepresented as a native 250 m soil cell.
"""

from .common import (
    RequestBudget,
    SourceCache,
    SourceError,
    fetch,
    number,
    quality,
    unavailable,
    utcnow,
)
from .models import Evidence, Source, SpatialSupport, TemporalSupport, Value

ENDPOINT = "https://rest.isric.org/soilgrids/v2.0/properties/query"
SOURCE = Source(
    provider="ISRIC",
    dataset="SoilGrids",
    api_version="v2.0",
    documentation=[
        "https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_01.html",
        "https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_02.html",
        "https://rest.isric.org/soilgrids/v2.0/docs",
    ],
    license="CC BY 4.0",
    attribution="ISRIC SoilGrids; point subset and documented unit conversions by EarthSync.",
)
# Mapped unit, divisor, output unit. No crop thresholds or drainage model.
PROPERTIES = {
    "phh2o": ("pH*10", 10, "pH"),
    "clay": ("g/kg", 10, "% by mass"),
    "sand": ("g/kg", 10, "% by mass"),
    "silt": ("g/kg", 10, "% by mass"),
    "soc": ("dg/kg", 10, "g/kg"),
    "nitrogen": ("cg/kg", 100, "g/kg"),
    "cec": ("mmol(c)/kg", 10, "cmol(c)/kg"),
    "bdod": ("cg/cm³", 100, "kg/dm³"),
}
STATS = ("mean", "Q0.05", "Q0.5", "Q0.95")
POLICY = "soilgrids-rest-units/1"
LIMITATIONS = [
    "Modeled regional point-query estimate, not an on-farm measurement or an area average.",
    "API v2.0 is not a dataset release; release, observation dates and native cell footprint are not supplied.",
    "Prediction quantiles describe modeled distributions, not measurement accuracy or confidence scores.",
    "No drainage, fertility, crop requirement or suitability inference is permitted.",
    "REST transport has not been live-validated in this environment; reference/probe use only.",
]


def read_soil(capture, query):
    payload = capture.json()
    try:
        if payload["type"] != "Feature" or payload["geometry"]["type"] != "Point":
            raise SourceError("SPATIAL_MISMATCH")
        coords = payload["geometry"]["coordinates"]
        if (
            not isinstance(coords, list)
            or len(coords) != 2
            or not all(number(v) for v in coords)
            or abs(coords[0] - query.point.longitude) > 1e-6
            or abs(coords[1] - query.point.latitude) > 1e-6
        ):
            raise SourceError("SPATIAL_MISMATCH")
        layers = payload["properties"]["layers"]
        if not isinstance(layers, list):
            raise SourceError("INVALID_RESPONSE")
        by_name = {}
        for layer in layers:
            name = layer["name"]
            if name in by_name or name not in PROPERTIES:
                raise SourceError("SOURCE_REVISION_MISMATCH")
            by_name[name] = layer
        values = []
        for prop, (mapped, divisor, unit) in PROPERTIES.items():
            layer = by_name.get(prop)
            depths = {}
            if layer is not None:
                metadata = layer["unit_measure"]
                if (
                    metadata.get("mapped_units") != mapped
                    or not number(metadata.get("d_factor"))
                    or metadata["d_factor"] != divisor
                ):
                    raise SourceError("UNIT_REVISION_MISMATCH")
                for depth in layer["depths"]:
                    label = depth["label"]
                    if label not in query.soil_depths or label in depths:
                        raise SourceError("DEPTH_MISMATCH")
                    top, bottom = map(int, label.removesuffix("cm").split("-"))
                    if depth["range"] != {
                        "top_depth": top,
                        "bottom_depth": bottom,
                        "unit_depth": "cm",
                    }:
                        raise SourceError("DEPTH_MISMATCH")
                    depths[label] = depth["values"]
            for label in query.soil_depths:
                top, bottom = map(int, label.removesuffix("cm").split("-"))
                stats = depths.get(label, {})
                if not isinstance(stats, dict):
                    raise SourceError("INVALID_RESPONSE")
                converted = []
                for statistic in STATS:
                    raw = stats.get(statistic)
                    present = number(raw) and raw >= 0
                    # Only documented physical bounds; no agronomic thresholds.
                    if present and prop in ("clay", "sand", "silt"):
                        present = raw <= 1000
                    if present and prop == "phh2o":
                        present = raw <= 140
                    missing = raw is None
                    converted.append(
                        Value(
                            variable=prop,
                            data_kind="modeled",
                            depth_cm=(top, bottom),
                            statistic=statistic,
                            original_value=raw if number(raw) else None,
                            original_unit=mapped if layer is not None else None,
                            value=raw / divisor if present else None,
                            unit=unit,
                            scale=1 / divisor,
                            quality="present"
                            if present
                            else "missing"
                            if missing
                            else "rejected",
                            reason=None
                            if present
                            else "ABSENT_VARIABLE"
                            if statistic not in stats
                            else "NULL_VALUE"
                            if missing
                            else "INVALID_VALUE",
                        )
                    )
                qs = converted[1:]
                if all(v.quality == "present" for v in qs) and not (
                    qs[0].value <= qs[1].value <= qs[2].value
                ):
                    for v in qs:
                        v.value, v.quality, v.reason = (
                            None,
                            "rejected",
                            "QUANTILE_ORDER",
                        )
                values.extend(converted)
        report = quality(
            values,
            ["DATASET_RELEASE_UNKNOWN", "NATIVE_FOOTPRINT_UNKNOWN"],
            quantiles=any(
                v.statistic != "mean" and v.quality == "present" for v in values
            ),
        )
        return Evidence(
            context_kind="soil",
            availability="unavailable"
            if report.present == 0
            else "partial"
            if report.missing or report.rejected
            else "reference_only",
            reason="NO_VALID_VALUES" if report.present == 0 else "REFERENCE_USE_ONLY",
            source=SOURCE.model_copy(deep=True),
            retrieval=capture.retrieval,
            spatial_support=SpatialSupport(
                query_point=query.point,
                returned_point=query.point,
                method="provider_REST_point_query_native_cell_unknown",
                nominal_resolution_m=250,
            ),
            temporal_support=TemporalSupport(
                kind="static_model",
                retrieved_at=capture.retrieval.retrieved_at,
                freshness="not_applicable",
            ),
            values=values,
            quality=report,
            limitations=LIMITATIONS,
        )
    except SourceError as exc:
        exc.retrieval = capture.retrieval
        raise
    except (KeyError, TypeError, ValueError, AttributeError) as exc:
        raise SourceError("INVALID_RESPONSE", capture.retrieval) from exc


class SoilGridsAdapter:
    def __init__(self, client, *, probe=False, now=utcnow, cache=None):
        self.client, self.probe, self.now = client, probe, now
        # Operational refetch interval, not a claim about scientific freshness.
        self.cache = cache or SourceCache(ttl=86400)
        self.budget = RequestBudget(limit=5, window=60)

    async def context(self, query):
        if not self.probe:
            return unavailable(
                "soil", SOURCE, query.point, "PROVIDER_REST_SERVICE_PAUSED"
            )
        key = (
            ENDPOINT,
            POLICY,
            query.point.latitude,
            query.point.longitude,
            tuple(sorted(query.soil_depths)),
            tuple(PROPERTIES),
            STATS,
        )

        async def load():
            if not self.budget.take():
                return unavailable(
                    "soil", SOURCE, query.point, "LOCAL_PROVIDER_RATE_LIMIT"
                )
            params = {
                "lon": query.point.longitude,
                "lat": query.point.latitude,
                "property": list(PROPERTIES),
                "depth": sorted(query.soil_depths),
                "value": list(STATS),
            }
            try:
                capture = await fetch(self.client, ENDPOINT, params, self.now)
                return read_soil(capture, query)
            except SourceError as exc:
                return unavailable("soil", SOURCE, query.point, exc.code, exc.retrieval)

        return await self.cache.get(key, load, self.now)
