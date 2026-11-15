"""Synthetic stored-result fixtures verify persistence and access boundaries."""

from uuid import uuid4

import pytest
from pydantic import ValidationError

from earthsync.platform_v1.comparisons import ComparisonInput, Comparisons
from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.models import ENGINE_VERSION
from earthsync.platform_v1.store import Store


def decision(store, farm, owner="alice", software_test=False, plans=2):
    return store.save_decision(
        owner,
        farm.id,
        {
            "engine_version": ENGINE_VERSION,
            "result": {
                "status": "success",
                "data": {
                    "software_test_only": software_test,
                    "context": {"scenarios": [{"plans": [{} for _ in range(plans)]}]},
                },
            },
        },
    )


def comparison(ids):
    return ComparisonInput(
        id=uuid4(),
        name="Declared baseline and alternatives",
        chosen_decision_id=ids[1],
        baseline_decision_id=ids[0],
        alternative_decision_ids=ids[1:],
        baseline_declared_existing_plan=True,
        priorities=["less_water", "nitrogen_potential"],
        exploration_reason="Farmer wishes to explore different reported plans",
    )


def test_three_distinct_strategies_restart_and_baseline_confirmation(store, farm_input):
    farm = store.create_farm("alice", farm_input)
    ids = [decision(store, farm) for _ in range(3)]
    value = comparison(ids)
    repo = Comparisons(store)
    saved = repo.save("alice", farm.id, value)
    assert saved["recommendation_eligible"] is False
    assert saved["chosen_decision_id"] == str(ids[1])
    assert saved["data_type"] == "farmer_reported"
    assert repo.save("alice", farm.id, value) == saved
    assert Comparisons(Store(store.path.parent)).list("alice", farm.id) == [saved]
    assert len(store.decisions("alice", farm.id)) == 3
    with pytest.raises(ValidationError):
        comparison(ids[:2])
    with pytest.raises(ValidationError):
        comparison([ids[0], ids[0], ids[2]])
    with pytest.raises(ValidationError):
        ComparisonInput(
            **{**value.model_dump(), "baseline_declared_existing_plan": False}
        )


def test_comparison_rejects_foreign_decisions_software_tests_and_single_crops(
    store, farm_input
):
    farm = store.create_farm("alice", farm_input)
    other = store.create_farm("alice", farm_input)
    ids = [decision(store, farm) for _ in range(2)]
    for bad, error in [
        (decision(store, other), "DECISION_NOT_OWNED_BY_FARM"),
        (decision(store, farm, software_test=True), "REAL_SAVED_ASSESSMENT_REQUIRED"),
        (decision(store, farm, plans=1), "SAVED_ROTATION_SEQUENCE_REQUIRED"),
    ]:
        with pytest.raises(PlatformError, match=error):
            Comparisons(store).save("alice", farm.id, comparison([*ids, bad]))
    assert Comparisons(store).list("alice", farm.id) == []
    with pytest.raises(PlatformError, match="NOT_FOUND"):
        Comparisons(store).list("bob", farm.id)
