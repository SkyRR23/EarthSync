"""Create labeled software scenarios; dates are invented, never sourced crop advice."""

from copy import deepcopy

from knowledge import index, project


def day(text):
    year, month, day = map(int, text.split("-"))
    return {"year": year, "month": month, "day": day}


def requests(data):
    profiles = index(data["profiles"])
    selected = {
        "ecocrop.1574@1": "rice.mm.calendar-5-sessions-0@1",
        "ecocrop.2150@1": "mung_bean.mm.rainfed-research@1",
        "ecocrop.1937@1": "sesame.mm.calendar-75-sessions-0@1",
        "ecocrop.2199@1": "groundnut.mm.calendar-65-sessions-0@1",
        "ecocrop.2175@1": "maize.mm.rainfed-research@1",
    }
    for label in ["wheat", "sorghum"]:
        p = profiles[label + ".us.tribune-reference@1"]
        selected[p["crop_id"]] = p["id"]
    # One synthetic field assertion authorizes only software calendar comparisons.
    source = {
        "id": "software-example-dates",
        "title": "Invented dates and field for contract tests",
        "citation": "EarthSync 7P software fixture; not farm history or crop calendar guidance",
        "url": None,
        "published_on": None,
        "reviewed_on": None,
        "review": "synthetic",
        "limitations": ["No agricultural validity or real field asserted."],
    }
    results = {}
    for rotation in data["rotations"]:
        request = {
            "schema_version": "earthsync.engine.v0.3.0",
            "day_basis": "synthetic Gregorian dates; no NASA LST/civil conversion",
            "mode": "software_test",
            "region_id": None,
            "approximate_user_location": None,
            "farm": {
                "field_id": "software-example-field",
                "point": {"latitude": 0, "longitude": 0},
                "boundary": None,
                "confirmed_on": day("2024-01-01"),
            },
            "photos": [],
            "climate_intent": "historical",
            "sources": [deepcopy(source)],
            "catalog": [],
            "observations": [],
            "climate": [],
            "history_complete": False,
            "history": [],
            "scenarios": [{"id": rotation["id"], "plans": []}],
            "sequential_field": True,
            "candidate_window": {
                "period": {"start": day("2027-01-01"), "end": day("2027-05-31")},
                "system": "rainfed",
            },
        }
        for i, cycle in enumerate(rotation["cycles"]):
            period = {"start": day(cycle["start"]), "end": day(cycle["end"])}
            if cycle["kind"] == "fallow":
                request["history"].append(
                    {
                        "id": "explicit-fallow",
                        "crop_id": None,
                        "profile_id": None,
                        "fallow": True,
                        "period": period,
                        "provenance": {
                            "kind": "synthetic",
                            "source_ids": [source["id"]],
                            "period": period,
                            "retrieved_on": day("2026-11-14"),
                            "issued_on": None,
                            "spatial": {
                                "scope": "field",
                                "field_id": "software-example-field",
                            },
                            "quality": "usable",
                            "uncertainty": "Invented example interval, not observed history",
                            "method": "software fixture",
                        },
                    }
                )
                continue
            p = profiles[selected[cycle["crop_id"]]]
            exported = project(
                data, p["id"], p["region_id"], p["production_system"], p["cultivar"]
            )["profile"]
            request["catalog"].append(exported)
            request["scenarios"][0]["plans"].append(
                {
                    "id": f"plan-{i + 1}",
                    "crop_id": p["crop_id"],
                    "profile_id": p["id"],
                    "system": exported["system"],
                    "cultivar": exported["cultivar"],
                    "period": period,
                }
            )
        results[rotation["id"] + ".request.json"] = request
    overlap = deepcopy(results["rice-mung.request.json"])
    overlap["scenarios"][0]["id"] = "declared-overlap"
    plans = overlap["scenarios"][0]["plans"]
    plans[1]["period"]["start"] = deepcopy(plans[0]["period"]["end"])
    results["declared-overlap.request.json"] = overlap
    reverse = deepcopy(results["rice-mung.request.json"])
    reverse["scenarios"][0]["id"] = "declared-reverse-order"
    reverse["scenarios"][0]["plans"].reverse()
    results["declared-reverse-order.request.json"] = reverse
    return results
