"""Daily MERRA2-only extension. Monthly v1 retrieval remains untouched."""

import hashlib
import json
import math
from datetime import timedelta

from ..errors import PlatformError
from ..models import Evidence, Measurement, Spatial, Temporal

ENDPOINT = "https://power.larc.nasa.gov/api/temporal/daily/point"
PARAMETERS = {
    "T2M_MIN": ("tmin", "C", "celsius"),
    "T2M_MAX": ("tmax", "C", "celsius"),
    "PRECTOTCORR": ("rainfall", "mm/day", "mm_per_day"),
}
POLICY = "power-daily-merra2.v1"


def evidence_id(document):
    return (
        "ev_"
        + hashlib.sha256(
            json.dumps(
                document, sort_keys=True, separators=(",", ":"), allow_nan=False
            ).encode()
        ).hexdigest()
    )


def number(value):
    return type(value) in (float, int) and math.isfinite(value)


def read_daily(capture, query, parameter):
    """One parameter per capture prevents aggregate headers hiding attribution."""
    if parameter not in PARAMETERS:
        raise PlatformError("UNSUPPORTED_PRODUCT")
    data = capture.json()
    try:
        if set(data["parameters"]) != {parameter} or set(
            data["properties"]["parameter"]
        ) != {parameter}:
            raise PlatformError("SCHEMA_MISMATCH", 502)
        header = data["header"]
        # Never infer day cutoffs or allow POWER/GEOSIT mixed attribution.
        expected_sources = (
            ["MERRA2"] if parameter == "PRECTOTCORR" else ["MERRA2", "POWER"]
        )
        if header["sources"] != expected_sources:
            raise PlatformError("UNSUPPORTED_SOURCE_LINEAGE", 502)
        if header["start"] != query.start.strftime("%Y%m%d") or header[
            "end"
        ] != query.end.strftime("%Y%m%d"):
            raise PlatformError("TEMPORAL_MISMATCH", 502)
        if header["time_standard"] != "LST":
            raise PlatformError("TEMPORAL_MISMATCH", 502)
        if header["api"]["version"] != "v2.10.3":
            raise PlatformError("SCHEMA_MISMATCH", 502)
        fill = header["fill_value"]
        variable, native_unit, unit = PARAMETERS[parameter]
        if not number(fill) or data["parameters"][parameter]["units"] != native_unit:
            raise PlatformError("UNIT_MISMATCH", 502)
        coordinates = data["geometry"]["coordinates"]
        if (
            data["geometry"]["type"] != "Point"
            or len(coordinates) not in (2, 3)
            or not all(number(v) for v in coordinates)
            or not -180 <= coordinates[0] <= 180
            or not -90 <= coordinates[1] <= 90
        ):
            raise PlatformError("SPATIAL_MISMATCH", 502)
        # Observed POWER v2.10.3 response point precision is three decimals.
        # Preserve returned geometry; this does not establish the native cell.
        if (
            abs(coordinates[0] - query.point.longitude) > 0.0005 + 1e-12
            or abs(coordinates[1] - query.point.latitude) > 0.0005 + 1e-12
        ):
            raise PlatformError("SPATIAL_MISMATCH", 502)
        daily = data["properties"]["parameter"][parameter]
        if not isinstance(daily, dict):
            raise PlatformError("SCHEMA_MISMATCH", 502)
        expected = [
            (query.start + timedelta(days=i)).strftime("%Y%m%d")
            for i in range((query.end - query.start).days + 1)
        ]
        if set(daily) - set(expected):
            raise PlatformError("TEMPORAL_MISMATCH", 502)
        measurements = []
        for key in expected:
            raw = daily.get(key)
            valid = (
                number(raw) and raw != fill and (parameter != "PRECTOTCORR" or raw >= 0)
            )
            measurements.append(
                Measurement(
                    variable=variable,
                    date=f"{key[:4]}-{key[4:6]}-{key[6:]}",
                    original_value=raw if number(raw) else None,
                    original_unit=native_unit,
                    value=raw if valid else None,
                    unit=unit,
                    conversion="identity; daily rate retained, no monthly interpolation",
                    quality="usable" if valid else "missing",
                    missing_reason=None
                    if valid
                    else "ABSENT_DAY"
                    if key not in daily
                    else "FILL_OR_INVALID_VALUE",
                )
            )
        document = dict(
            provider="NASA POWER",
            dataset="POWER daily meteorology / MERRA-2"
            if parameter == "PRECTOTCORR"
            else "POWER hourly-derived daily extrema / MERRA-2",
            dataset_version=header["api"]["version"],
            source_url=ENDPOINT,
            source_identifier=f"{POLICY}:{parameter}",
            data_type="modeled",
            spatial=Spatial(
                role="regional_context",
                query_point=query.point,
                original_geometry=data["geometry"],
                support="Native modeled grid context queried at point; not farm measurements or polygon average",
                resolution_degrees=(0.5, 0.625),
            ),
            temporal=Temporal(
                start=query.start,
                end=query.end,
                retrieved_at=capture.retrieved_at,
                day_basis="NASA_POWER_LST",
            ),
            measurements=measurements,
            quality_flags=["REGIONAL_MODEL_NOT_FIELD_OBSERVATION"],
            missing_reasons=sorted(
                {m.missing_reason for m in measurements if m.missing_reason}
            ),
            limitations=[
                "Daily coverage is not proof of local scientific accuracy.",
                "LST is solar-time swath, not civil farm calendar; no timezone conversion inferred.",
                "No forecast, ET0, GDD or recommendation calculated by Python.",
            ],
            usable_for_assessment=True,
            review="reviewed",
            response_sha256=capture.sha256,
            source_metadata={
                "policy": POLICY,
                "parameter": parameter,
                "header": header,
                "parameters": data["parameters"],
                "messages": data.get("messages", []),
                "http_headers": capture.headers,
                "lineage": {
                    "provider_sources": expected_sources,
                    "attribution": "single-parameter header plus pinned NASA parameter catalog and methodology",
                    "source_review": "NASA-daily-source-review.v1",
                },
                "review_scope": "Technical metadata and transport contract only; no agronomic applicability approval",
            },
        )
        serializable = json.loads(
            json.dumps(
                document,
                default=lambda v: json.loads(v.model_dump_json())
                if hasattr(v, "model_dump_json")
                else str(v),
            )
        )
        return Evidence(id=evidence_id(serializable), **document)
    except PlatformError:
        raise
    except (KeyError, TypeError, ValueError, IndexError) as exc:
        raise PlatformError("SCHEMA_MISMATCH", 502) from exc


class PowerDaily:
    def __init__(self, transport):
        self.transport = transport

    async def retrieve(self, query):
        # Sequential, provider-friendly calls, within the enclosing job deadline.
        records, gaps = [], []
        for parameter in PARAMETERS:
            try:
                capture = await self.transport.get(
                    ENDPOINT,
                    {
                        "parameters": parameter,
                        "community": "AG",
                        "latitude": query.point.latitude,
                        "longitude": query.point.longitude,
                        "start": query.start.strftime("%Y%m%d"),
                        "end": query.end.strftime("%Y%m%d"),
                        "format": "JSON",
                        "time-standard": "LST",
                    },
                )
                records.append(read_daily(capture, query, parameter))
            except PlatformError as exc:
                gaps.append(
                    {
                        "parameter": parameter,
                        "code": exc.code,
                        "retryable": exc.retryable,
                    }
                )
        low = next((r for r in records if r.measurements[0].variable == "tmin"), None)
        high = next((r for r in records if r.measurements[0].variable == "tmax"), None)
        if low and high:
            if any(
                a.value is not None and b.value is not None and a.value > b.value
                for a, b in zip(low.measurements, high.measurements, strict=True)
            ):
                raise PlatformError("SCIENTIFIC_QUALITY_REJECTION", 422)
        return {
            "records": [r.model_dump(mode="json") for r in records],
            "gaps": gaps,
            "contract_version": POLICY,
        }
