"""Calendar relationships only. No biological stage or bare-soil inference."""

from datetime import date, timedelta

from .journal import Journal


def calendar_intervals(history, reports):
    periods = []
    for row in history:
        periods.append(
            {
                "id": row["id"],
                "start": row["start"],
                "end": row["end"],
                "kind": "fallow" if row["fallow"] else "crop",
                "crop_id": row["crop_id"],
                "label": "Declared fallow"
                if row["fallow"]
                else row["crop_id"] or "Crop identity unknown",
            }
        )
    seen = {(p["start"], p["end"], p["crop_id"], p["kind"]) for p in periods}
    for row in reports:
        if row["kind"] not in {"season", "fallow", "bare_field"}:
            continue
        kind = "crop" if row["kind"] == "season" else row["kind"]
        key = (row["occurred_on"], row["harvest_on"], row["crop_id"], kind)
        if key not in seen:
            periods.append(
                {
                    "id": row["id"],
                    "start": row["occurred_on"],
                    "end": row["harvest_on"],
                    "kind": kind,
                    "crop_id": row["crop_id"],
                    "label": row["crop_name"] or kind,
                }
            )
            seen.add(key)
    periods.sort(key=lambda p: (p["start"], p["id"]))
    gaps, overlaps = [], []
    covered_until = None
    for i, current in enumerate(periods):
        start = date.fromisoformat(current["start"])
        end = date.fromisoformat(current["end"]) if current["end"] else date.today()
        if covered_until is not None and start > covered_until + timedelta(days=1):
            gaps.append(
                {
                    "start": str(covered_until + timedelta(days=1)),
                    "end": str(start - timedelta(days=1)),
                    "status": "unknown",
                    "explanation": "No operation was reported for these dates. This is not evidence of fallow or bare soil.",
                }
            )
        covered_until = max(covered_until or end, end)
        for prior in periods[:i]:
            prior_end = (
                date.fromisoformat(prior["end"]) if prior["end"] else date.today()
            )
            if start <= prior_end:
                overlaps.append(
                    {
                        "first_id": prior["id"],
                        "second_id": current["id"],
                        "start": current["start"],
                        "end": str(min(end, prior_end)),
                        "status": "reported_period_overlap",
                        "explanation": "Reported periods overlap. Confirm intercropping, dates or separate fields; no crop feasibility conclusion is inferred.",
                    }
                )
    return {"periods": periods, "unknown_gaps": gaps, "overlaps": overlaps}


def timeline(store, owner, farm_id):
    store.farm(owner, farm_id)
    result = calendar_intervals(
        store.history(owner, farm_id), Journal(store).list(owner, farm_id)
    )
    return {
        "schema_version": "earthsync.timeline.v1",
        **result,
        "limitations": [
            "Calendar days do not determine biological stage.",
            "Unreported periods are unknown, not inferred fallow or bare soil.",
            "Historical climate, reference ET0 and satellite/model pixels retain their own native resolution and quality.",
        ],
    }
