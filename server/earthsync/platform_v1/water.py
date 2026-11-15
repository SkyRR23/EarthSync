"""Validated POWER inputs → actual Rust FAO-56 → immutable evidence, never advice."""

from datetime import timedelta, datetime, timezone
import hashlib
import json

from .errors import PlatformError
from .models import Evidence, Measurement, Spatial, Temporal
from .providers.power_daily import ENDPOINT, PARAMETERS, evidence_id, read_daily

POLICY = "power-fao56-inputs.v1"
METHOD = "fao56-daily-pm.v1"
FAO = "https://www.fao.org/4/X0490E/x0490e08.htm"
PARAMS = {
    **PARAMETERS,
    "T2MDEW": ("dewpoint", "C", "celsius"),
    "WS2M": ("wind_2m", "m/s", "m_per_s"),
    "PS": ("pressure", "kPa", "kPa"),
    "ALLSKY_SFC_SW_DWN": ("solar_radiation", "MJ/m^2/day", "MJ_per_m2_day"),
}
CONTRACT = {
    "policy": POLICY,
    "parameters": PARAMS,
    "sources": {
        "T2M_MIN": ["MERRA2", "POWER"],
        "T2M_MAX": ["MERRA2", "POWER"],
        "PRECTOTCORR": ["MERRA2"],
        "T2MDEW": ["MERRA2"],
        "WS2M": ["MERRA2", "POWER"],
        "PS": ["MERRA2"],
        "ALLSKY_SFC_SW_DWN": ["SYN1DEG"],
    },
}
LIMITATIONS = [
    "Calculated historical reference-grass ET0 from regional modeled/satellite-derived inputs, not a field observation or forecast.",
    "MERRA-2 meteorology (0.5 by 0.625 degrees) and SYN1deg radiation (1 degree) are distinct spatial supports, aligned only by requested point and NASA LST date.",
    "NASA LST is a 15-degree solar-time swath, not the farmer's civil calendar. Provider elevation is model terrain, not surveyed field elevation.",
    "Daily dewpoint is used in FAO-56 Eq.14; vapour pressure from mean dewpoint approximates mean daily vapour pressure. Below-freezing Dew/Frost Point phase conversion is unvalidated and withheld. No field accuracy or calibrated uncertainty interval is established.",
    "FAO-56 daily reference grass: albedo 0.23, G=0; clear-sky Rs/Rso capped at 1. Polar night, negative cloud factor, negative ET0 and incompatible inputs are withheld.",
    "ET0 is not ETc, effective rain, root-zone depletion, irrigation requirement, water stress or proof of water availability.",
]


def water_dependencies(system):
    common = {
        "etc": [
            "Independently accepted crop/cultivar/system Kc stages, actual stage dates and local adjustments",
            "FAO-56 Eq.66 linear development/late-stage interpolation; four constant endpoint stages do not preserve the method (7V review)",
            "Complete aligned ET0",
        ],
        "effective_rainfall": [
            "Field rainfall and accepted runoff/infiltration/interception method"
        ],
        "soil_water_storage": [
            "Depth-specific field capacity and wilting point, effective root depth and initial water content"
        ],
        "root_zone_depletion": [
            "Initial depletion, daily effective rain, ETc, capillary rise, irrigation and deep percolation"
        ],
        "net_irrigation": [
            "Accepted depletion target and complete field water balance"
        ],
        "gross_irrigation": [
            "Net irrigation and measured application/conveyance efficiency"
        ],
        "actual_availability": [
            "Farmer-confirmed source, allocation, delivery capacity and dates"
        ],
        "water_stress": [
            "Actual root-zone depletion, accepted readily available water and crop stress parameters"
        ],
    }
    if system == "flooded_lowland":
        common["paddy_water_balance"] = [
            "Land preparation/saturation, seepage/percolation, bund/storage depth, drainage and standing-water targets"
        ]
    return {
        key: {"value": None, "status": "missing", "required": value}
        for key, value in common.items()
    }


class WaterPipeline:
    def __init__(self, transport, engine):
        self.transport, self.engine = transport, engine

    async def retrieve(self, query):
        # This bounded accepted historical contract does not splice SRB,
        # FLASHFlux, GEOSIT or mixed transition periods into MERRA-2/SYN1deg.
        if query.start.year < 2001:
            raise PlatformError("UNSUPPORTED_WATER_PRODUCT_PERIOD", 422)
        records, gaps = [], []
        for parameter in PARAMS:
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
                record = read_daily(capture, query, parameter, contract=CONTRACT)
                records.append(record)
            except PlatformError as exc:
                gaps.append(
                    {
                        "parameter": parameter,
                        "code": exc.code,
                        "retryable": exc.retryable,
                    }
                )
        return {
            "records": [r.model_dump(mode="json") for r in records],
            "gaps": gaps,
            "contract_version": POLICY,
        }

    async def calculate(self, records, query):
        records = [Evidence.model_validate(r) for r in records]
        inputs = {r.source_metadata["parameter"]: r for r in records}
        geometries = [r.spatial.original_geometry for r in records]
        # A common returned elevation/point is necessary, but does not imply
        # common native meteorological/radiation cells.
        if geometries and any(g != geometries[0] for g in geometries):
            raise PlatformError("SPATIAL_MISMATCH", 422)
        geometry = geometries[0] if geometries else None
        elevation = (
            geometry["coordinates"][2]
            if geometry and len(geometry["coordinates"]) == 3
            else None
        )
        maps = {
            key: {
                str(m.date): m.value if m.quality == "usable" else None
                for m in r.measurements
            }
            for key, r in inputs.items()
        }
        days = []
        fields = {
            "tmin_c": "T2M_MIN",
            "tmax_c": "T2M_MAX",
            "dewpoint_c": "T2MDEW",
            "wind_2m_m_s": "WS2M",
            "pressure_kpa": "PS",
            "solar_mj_m2_day": "ALLSKY_SFC_SW_DWN",
            "rainfall_mm": "PRECTOTCORR",
        }
        for i in range((query.end - query.start).days + 1):
            day = query.start + timedelta(days=i)
            days.append(
                {
                    "date": {"year": day.year, "month": day.month, "day": day.day},
                    **{
                        field: maps.get(param, {}).get(str(day))
                        for field, param in fields.items()
                    },
                }
            )
        request = {
            "method": METHOD,
            "latitude": query.point.latitude,
            "elevation_m": elevation,
            "day_basis": "NASA_POWER_LST",
            "days": days,
        }
        result = await self.engine.water(request)
        digest = hashlib.sha256(
            json.dumps(result, sort_keys=True, allow_nan=False).encode()
        ).hexdigest()
        measurements = []
        for i, day in enumerate(result["days"]):
            measurements.append(
                Measurement(
                    variable="et0",
                    date=query.start + timedelta(days=i),
                    original_value=day["et0_mm"],
                    original_unit="mm/day",
                    value=day["et0_mm"],
                    unit="mm_per_day",
                    conversion="FAO-56 daily Penman–Monteith; calculated once in compiled Rust",
                    quality="usable" if day["et0_mm"] is not None else "missing",
                    missing_reason=day.get("missing_reason"),
                )
            )
        document = dict(
            provider="EarthSync Rust / NASA POWER",
            dataset="Calculated FAO-56 reference-grass ET0",
            dataset_version=METHOD,
            source_url=FAO,
            source_identifier=METHOD,
            data_type="modeled",
            spatial=Spatial(
                role="regional_context",
                query_point=query.point,
                original_geometry=geometry,
                support="MERRA-2 0.5° × 0.625° meteorology and SYN1deg 1° radiation at query point; not field measurements",
            ),
            temporal=Temporal(
                start=query.start,
                end=query.end,
                retrieved_at=datetime.now(timezone.utc),
                day_basis="NASA_POWER_LST",
            ),
            measurements=measurements,
            quality_flags=["DERIVED_REGIONAL_REFERENCE_ET0"],
            missing_reasons=sorted(
                {m.missing_reason for m in measurements if m.missing_reason}
            ),
            limitations=LIMITATIONS,
            usable_for_assessment=True,
            review="reviewed",
            response_sha256=digest,
            source_metadata={
                "policy": METHOD,
                "parameter": "et0",
                "calculation": result,
                "parent_evidence_ids": [r.id for r in records],
                "parent_response_sha256": {r.id: r.response_sha256 for r in records},
                "engine_binary_sha256": self.engine.sha256,
                "hash_scope": "SHA-256 of canonical calculated result, not a provider HTTP response",
                "review_scope": "Numerical method and provider semantics; no independent field/crop applicability approval",
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
