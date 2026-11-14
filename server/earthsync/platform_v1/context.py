"""Explicit adapter to PR #14 assistant.v1-proposal, using actual source refs."""

import hashlib
import json


def assistant_context(store, owner, farm_id):
    farm = store.farm(owner, farm_id)
    records = store.farm_records(owner, farm_id)
    # Keep within PR #14's 120-record context limit. Do not invent aggregates or
    # mark raw daily values as Rust calculations. A deterministic latest-day
    # projection is explicit; full time series remains in the evidence endpoint.
    sources, evidence = [], []
    for record in records[:100]:
        if record.data_type == "reference":
            continue
        sources.append(
            {
                "id": record.id,
                "provider": record.provider,
                "title": record.dataset,
                "url": record.source_url,
            }
        )
        last = record.measurements[-1] if record.measurements else None
        if last:
            evidence.append(
                {
                    "id": record.id,
                    "topic": "rainfall"
                    if last.variable == "rainfall"
                    else "temperature"
                    if last.variable in ("tmin", "tmax")
                    else "soil",
                    "metric": last.variable + "_latest_daily_record",
                    "kind": record.data_type,
                    "quality": "available"
                    if last.quality == "usable" and record.usable_for_assessment
                    else "missing"
                    if last.value is None
                    else "unverified",
                    "value": last.value,
                    "unit": last.unit,
                    "start_date": str(last.date) if last.date else None,
                    "end_date": str(last.date) if last.date else None,
                    "retrieved_at": record.temporal.retrieved_at.isoformat(),
                    "spatial_support": record.spatial.support,
                    "scope": "regional",
                    "location_id": str(farm.id),
                    "source_ids": [record.id],
                    "limitations": record.limitations
                    + [
                        "Latest daily source record only; not a seasonal aggregate, forecast or farm measurement."
                    ],
                    "calculation": "none",
                }
            )
    value = {
        "schema_version": "assistant.v1-proposal",
        "context_id": "pending",
        "approximate_location": None,
        "selected_area": None,
        "confirmed_farm": {
            "id": str(farm.id),
            "point": farm.confirmed_point.model_dump(),
            "boundary": [
                {"longitude": x, "latitude": y}
                for x, y in farm.confirmed_polygon.coordinates[0]
            ]
            if farm.confirmed_polygon
            and len(farm.confirmed_polygon.coordinates[0]) <= 500
            else [],
        },
        "sources": sources,
        "evidence": evidence,
        "decisions": [],
        "limitations": [
            "No reviewed positive crop recommendations. Full evidence and Rust decision details are available separately.",
            "Only source records are projected; reference-only inputs must not be promoted. Boundaries exceeding assistant v1 limits are omitted; full farm geometry remains in farm context.",
        ],
    }
    value["context_id"] = (
        "ctx_" + hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
    )
    return value
