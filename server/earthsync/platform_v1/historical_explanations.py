"""Deterministic assistant sidecars from saved accepted historical summaries."""

import json


def historical_references(store, owner, farm_id):
    store.farm(owner, farm_id)
    with store.connection() as db:
        rows = db.execute(
            "SELECT document FROM historical_windows WHERE owner=? AND farm_id=? ORDER BY created DESC LIMIT 100",
            (owner, str(farm_id)),
        ).fetchall()
    windows, seen = [], set()
    for row in rows:
        w = json.loads(row[0])
        if (w["start"], w["end"]) not in seen:
            seen.add((w["start"], w["end"]))
            windows.append(w)
    sources, evidence = [], []
    windows.sort(key=lambda w: (w["start"], w["end"]), reverse=True)
    for w in windows[:12]:
        source_id = "history:" + w["id"]
        sources.append(
            {
                "id": source_id,
                "provider": "NASA POWER / EarthSync Rust",
                "title": "Saved historical period with pinned parent evidence",
                "url": "https://power.larc.nasa.gov/docs/services/api/temporal/daily/",
            }
        )
        for variable, topic in [
            ("rainfall", "rainfall"),
            ("temperature", "temperature"),
            ("et0", "climate"),
        ]:
            m = w["summary"]["metrics"][variable]
            text = (
                f"Historical {variable}: {m['value'] if m['value'] is not None else 'unavailable'} {m['unit']}; {w['start']} to {w['end']} NASA POWER LST; {m['valid_days']}/{m['expected_days']} accepted days, {m['missing_days']} missing. Method: {m['method']}. "
                + (
                    "Complete period."
                    if m["status"] == "complete"
                    else "Accepted-day statistic only; complete-period result unavailable."
                )
            )
            evidence.append(
                {
                    "id": source_id + ":" + variable,
                    "topic": topic,
                    "metric": "historical_period_summary",
                    "kind": "modeled",
                    "quality": "unverified",
                    "value": text[:500],
                    "start_date": w["start"],
                    "end_date": w["end"],
                    "retrieved_at": max(w["retrieved_at"].values()),
                    "spatial_support": "Regional query-point context, not a polygon average or field observation",
                    "scope": "regional",
                    "location_id": str(farm_id),
                    "source_ids": [source_id],
                    "limitations": [
                        "Saved historical descriptive summary; source coverage is not field accuracy. Not current weather or a forecast."
                    ],
                }
            )
    if len(windows) >= 2:
        a, b = windows[0], windows[1]
        av, bv = (
            a["summary"]["metrics"]["rainfall"],
            b["summary"]["metrics"]["rainfall"],
        )
        if av["complete_value"] is not None and bv["complete_value"] is not None:
            text = f"Historical rainfall: {a['start']}–{a['end']} = {av['value']:.2f} mm ({av['valid_days']} days); {b['start']}–{b['end']} = {bv['value']:.2f} mm ({bv['valid_days']} days). First minus second = {av['value'] - bv['value']:.2f} mm. Direct difference of complete daily sums; unequal period lengths are not adjusted. Not climate-change attribution or a crop-damage prediction."
            evidence.insert(
                0,
                {
                    **evidence[0],
                    "id": "historical-rain-comparison:" + a["id"],
                    "metric": "historical_comparison",
                    "value": text[:500],
                    "source_ids": ["history:" + a["id"], "history:" + b["id"]],
                },
            )
    return sources, evidence
