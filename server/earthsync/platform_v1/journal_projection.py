"""Project only explicitly selected farmer reports into supported v0.3 fields."""

from datetime import date, datetime

from .errors import PlatformError
from .journal import Journal


def selected_reports(store, owner, farm_id, ids):
    reports = {r["id"]: r for r in Journal(store).list(owner, farm_id)}
    if any(str(ident) not in reports for ident in ids):
        raise PlatformError("REPORT_NOT_OWNED_BY_FARM", 404)
    return [reports[str(ident)] for ident in ids]


def project_reports(reports, request):
    from .orchestrate import engine_date

    for report in reports:
        # Plans, priorities and resources are retained as farmer context only.
        if report["kind"] == "plan":
            continue
        values = []
        if report["drainage"] != "unknown":
            values.append(
                (
                    "drainage",
                    {"type": "category", "value": report["drainage"]},
                    "category",
                    None,
                )
            )
        if report["irrigation"] in {"available", "none"}:
            values.append(
                (
                    "irrigation_available",
                    {"type": "boolean", "value": report["irrigation"] == "available"},
                    "boolean",
                    None,
                )
            )
        soil = report.get("soil_test")
        if soil and soil["property"] in {"ph", "organic_carbon"}:
            values.append(
                (
                    "ph" if soil["property"] == "ph" else "organic_carbon",
                    {"type": "number", "value": soil["value"]},
                    "ph" if soil["property"] == "ph" else "g_per_kg",
                    {"top_cm": soil["top_cm"], "bottom_cm": soil["bottom_cm"]},
                )
            )
        if not values:
            continue
        ident = "farmer-report:" + report["id"]
        request["sources"].append(
            {
                "id": ident,
                "title": "Explicitly selected farmer report",
                "citation": f"Farmer journal {report['id']} dated {report['occurred_on']}",
                "url": None,
                "published_on": None,
                "reviewed_on": None,
                "review": "unreviewed",
                "limitations": [
                    "Farmer-reported, not independently verified. Availability is not irrigation sufficiency. Calendar applicability requires review."
                ],
            }
        )
        day = engine_date(date.fromisoformat(report["occurred_on"]))
        for prop, value, unit, depth in values:
            request["observations"].append(
                {
                    "id": ident + ":" + prop,
                    "property": prop,
                    "value": value,
                    "unit": unit,
                    "depth": depth,
                    "provenance": {
                        "kind": "farmer_reported",
                        "source_ids": [ident],
                        "period": {"start": day, "end": day},
                        "retrieved_on": engine_date(
                            datetime.fromisoformat(report["recorded_at"]).date()
                        ),
                        "issued_on": None,
                        "spatial": {
                            "scope": "field",
                            "field_id": request["farm"]["field_id"],
                        },
                        "quality": "usable",
                        "uncertainty": "Unverified farmer report; date-specific, not a permanent field measurement",
                        "method": "explicit_journal_selection.v1; farmer_calendar_unmapped",
                    },
                }
            )
