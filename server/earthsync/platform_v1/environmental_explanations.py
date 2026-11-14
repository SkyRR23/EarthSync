"""Read-only explanation sidecars from validated 7G source snapshots.

These are never converted to accepted Rust crop/soil requirements or forecasts.
"""

from datetime import datetime, timezone


def assistant_references(store, owner, farm_id, now=None):
    now = now or datetime.now(timezone.utc)
    sources, evidence, seen = [], [], set()
    for job in store.intelligence(owner, farm_id):
        if job["status"] != "succeeded" or job["kind"] in seen:
            continue
        value = job["result"]
        if job["kind"] == "soil_map":
            cells = [c for c in value.get("cells", []) if c.get("at_query_point")]
            reading = cells[0]["value"] if cells else None
            url = value.get("source_url")
            summary = f"Reference-only modeled SoilGrids query cell: {reading if reading is not None else 'unknown'} pH; depth {value['depth_cm']} cm; native {value['resolution_m']} m grid. Field sampling date and prediction intervals are unavailable. Not a farm laboratory result or accepted crop requirement. Original retrieval {value['retrieved_at']}."
            topic, metric, kind, quality = (
                "soil",
                "soil_reference_summary",
                "modeled",
                "unverified",
            )
        elif job["kind"] == "forecast":
            rows = value.get("records", [])
            url = rows[0].get("source_url") if rows else None
            future = [r for r in rows if datetime.fromisoformat(r["valid_at"]) > now]
            retrieved = datetime.fromisoformat(value["retrieved_at"])
            stale = (now - retrieved).total_seconds() >= 1800 or not future
            first = future[0] if future else rows[0] if rows else None
            summary = f"{'Stale/expired' if stale else 'Dated'} NOAA GFS temperature reference; native {value['grid_spacing_degrees']} degree model grid. Model initialization {value['model_initialized_at']}, publication/issuance unknown. "
            if first:
                summary += f"Sample valid {first['valid_at']}: {first['temperature_c']} deg C. "
            summary += "Sparse model times, not current observations, an official warning or crop-damage prediction."
            topic, metric, kind, quality = (
                "climate",
                "forecast_reference_summary",
                "forecast",
                "stale" if stale else "unverified",
            )
        else:
            continue
        if not url or not url.startswith("https://"):
            continue
        seen.add(job["kind"])
        ident = "source-reference:" + job["id"]
        sources.append(
            {
                "id": ident,
                "provider": value["provider"],
                "title": value["dataset"],
                "url": url,
            }
        )
        evidence.append(
            {
                "id": ident,
                "topic": topic,
                "metric": metric,
                "kind": kind,
                "quality": quality,
                "value": summary[:500],
                "retrieved_at": value["retrieved_at"],
                "spatial_support": "Regional modeled reference; native support retained in source snapshot",
                "scope": "regional",
                "location_id": str(farm_id),
                "source_ids": [ident],
                "limitations": value["limitations"][:20],
                "calculation": "none",
            }
        )
    return sources, evidence
