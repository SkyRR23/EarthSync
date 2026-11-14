from earthsync.platform_v1.farmer_timeline import calendar_intervals


def test_gap_unknown_explicit_fallow_and_overlap():
    rows = [
        {
            "id": "one",
            "start": "2024-01-01",
            "end": "2024-01-31",
            "fallow": False,
            "crop_id": "rice@1",
        },
        {
            "id": "two",
            "start": "2024-03-01",
            "end": "2024-03-31",
            "fallow": True,
            "crop_id": None,
        },
        {
            "id": "three",
            "start": "2024-03-15",
            "end": "2024-04-01",
            "fallow": False,
            "crop_id": "sesame@1",
        },
    ]
    result = calendar_intervals(rows, [])
    assert result["unknown_gaps"] == [
        {
            "start": "2024-02-01",
            "end": "2024-02-29",
            "status": "unknown",
            "explanation": "No operation was reported for these dates. This is not evidence of fallow or bare soil.",
        }
    ]
    assert len(result["overlaps"]) == 1
    assert result["overlaps"][0]["start"] == "2024-03-15"
    assert result["periods"][1]["kind"] == "fallow"
    assert result["periods"][0]["kind"] == "crop"


def test_projected_journal_duplicate_and_future_plan_do_not_create_conflict():
    history = [
        {
            "id": "history",
            "start": "2024-01-01",
            "end": "2024-02-01",
            "fallow": False,
            "crop_id": "rice@1",
        }
    ]
    report = {
        "id": "journal",
        "occurred_on": "2024-01-01",
        "harvest_on": "2024-02-01",
        "kind": "season",
        "crop_id": "rice@1",
        "crop_name": "Reported rice",
    }
    result = calendar_intervals(history, [report, {**report, "kind": "plan"}])
    assert len(result["periods"]) == 1
    assert result["overlaps"] == []
