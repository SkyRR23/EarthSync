"""Explicit adapter to PR #14 assistant.v1-proposal, using actual source refs."""

import hashlib
import json

from .journal import Journal


def assistant_context(store, owner, farm_id):
    farm = store.farm(owner, farm_id)
    records = store.farm_records(owner, farm_id)
    # Keep within PR #14's 120-record context limit. Do not invent aggregates or
    # mark raw daily values as Rust calculations. A deterministic latest-day
    # projection is explicit; full time series remains in the evidence endpoint.
    sources, evidence, decisions, reference_facts = [], [], [], []
    for record in records[:40]:
        if record.data_type in ("reference", "synthetic"):
            continue
        sources.append(
            {
                "id": record.id,
                "provider": record.provider,
                "title": record.dataset,
                "url": record.source_url,
            }
        )
        if record.source_metadata.get("policy") == "fao56-daily-pm.v1":
            calculation = record.source_metadata["calculation"]
            for metric, topic, key in [
                ("et0_total", "climate", "et0_total_mm"),
                ("rainfall_total", "rainfall", "rainfall_total_mm"),
            ]:
                value = calculation.get(key)
                evidence.append(
                    {
                        "id": record.id + (":et0" if topic == "climate" else ":rain"),
                        "topic": topic,
                        "metric": metric,
                        "kind": "modeled",
                        "quality": "available" if value is not None else "missing",
                        "value": value,
                        "unit": "mm",
                        "start_date": str(record.temporal.start),
                        "end_date": str(record.temporal.end),
                        "retrieved_at": record.temporal.retrieved_at.isoformat(),
                        "spatial_support": record.spatial.support,
                        "scope": "regional",
                        "location_id": str(farm.id),
                        "source_ids": [record.id],
                        "limitations": record.limitations,
                        "calculation": "rust",
                    }
                )
            continue
        if record.measurements and record.measurements[0].variable not in (
            "rainfall",
            "tmin",
            "tmax",
        ):
            continue
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
    # Preserve persisted engine states and original citation IDs. No request,
    # photo bytes, coordinates from photos, tokens or private object paths.
    for decision in store.decisions(owner, farm_id)[:3]:
        for sidecar in decision["assessment"].get("catalog_projection", [])[:5]:
            profile = sidecar.get("profile", {})
            duration = profile.get("parameters", {}).get("growing_duration", {})
            if duration.get("state") != "available":
                continue
            claim_ids = set(duration["claim_ids"])
            ids = {
                c["source_id"]
                for c in sidecar.get("claims", [])
                if c["id"] in claim_ids
            }
            linked = []
            for source in sidecar.get("sources", []):
                if source["id"] not in ids:
                    continue
                if source["id"] not in {s["id"] for s in sources} and len(sources) < 70:
                    sources.append(
                        {
                            "id": source["id"],
                            "provider": source["publisher"],
                            "title": source["title"],
                            "url": source["url"],
                        }
                    )
                if source["id"] in {s["id"] for s in sources}:
                    linked.append(source["id"])
            if linked:
                reference_facts.append(
                    {
                        "profile_id": profile["id"],
                        "parameter": "growing_duration",
                        "value_text": json.dumps(duration["value"], ensure_ascii=False),
                        "unit": duration["unit"],
                        "scope": duration["spatial_support"][:500],
                        "source_ids": linked,
                    }
                )
        result = decision["assessment"]["result"].get("data", {})
        retained = {s["id"] for s in sources}
        for source in result.get("context", {}).get("sources", [])[:10]:
            if source["id"] not in retained and len(sources) < 70:
                sources.append(
                    {
                        "id": source["id"],
                        "provider": "Persisted Rust source",
                        "title": source["title"],
                        "url": source.get("url"),
                    }
                )
                retained.add(source["id"])
        for index, summary in enumerate(result.get("summaries", [])[:5]):
            ids = list(
                dict.fromkeys(
                    s
                    for f in result.get("findings", [])
                    if f["scenario_id"] == summary["scenario_id"]
                    for s in f["source_ids"]
                )
            )
            decisions.append(
                {
                    "id": f"{decision['id']}:{index}",
                    "scenario_id": summary["scenario_id"],
                    "status": summary["status"],
                    "synthetic": False,
                    "explanation": " ".join(
                        f["explanation"]
                        for f in result.get("findings", [])
                        if f["scenario_id"] == summary["scenario_id"]
                    )[:1000]
                    or None,
                    "source_ids": [s for s in ids if s in retained][:20],
                    "evidence_ids": [],
                    "limitations": [
                        "Persisted reference assessment; no crop recommendation."
                    ],
                }
            )
    # Farmer reports are displayed as attributed records, never scientific inputs.
    for report in Journal(store).list(owner, farm_id)[:10]:
        summary = f"{report['kind']}; crop={report['crop_name'] or 'unknown'}; stage={report['stage']}; priorities={','.join(report['priorities']) or 'unknown'}; notes={report['notes']}"
        evidence.append(
            {
                "id": "journal:" + report["id"],
                "topic": "farmer_input",
                "metric": "journal_report",
                "kind": "farmer_reported",
                "quality": "unverified",
                "value": summary[:500],
                "start_date": report["occurred_on"],
                "end_date": report["harvest_on"] or report["occurred_on"],
                "retrieved_at": report["recorded_at"],
                "scope": "field",
                "location_id": str(farm.id),
                "source_ids": [],
                "limitations": [
                    "Farmer report, not independently verified. Plans are not completed operations."
                ],
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
        "decisions": decisions,
        "reference_facts": reference_facts,
        "limitations": [
            "No reviewed positive crop recommendations. Full evidence and Rust decision details are available separately.",
            "Only source records are projected; reference-only inputs must not be promoted. Boundaries exceeding assistant v1 limits are omitted; full farm geometry remains in farm context.",
        ],
    }
    value["context_id"] = (
        "ctx_" + hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
    )
    return value
