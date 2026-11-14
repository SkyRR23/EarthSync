"""Synthetic stored findings test retrieval/attribution, not agricultural validity."""

from uuid import uuid4

from earthsync.assistant.models import ChatRequest
from earthsync.assistant.service import explain
from earthsync.platform_v1.comparisons import Comparisons, ComparisonInput
from earthsync.platform_v1.context import assistant_context
from earthsync.platform_v1.journal import Journal, JournalInput
from earthsync.platform_v1.models import ENGINE_VERSION


def test_default_comparison_answer_retains_baseline_and_both_alternatives(
    store, farm_input
):
    farm = store.create_farm("alice", farm_input)
    ids = []
    for i in range(3):
        plans = [
            {
                "profile_id": f"software-test-crop-{i}-{j}",
                "period": {
                    "start": {"year": 2024, "month": 1 + j, "day": 1},
                    "end": {"year": 2024, "month": 1 + j, "day": 20},
                },
            }
            for j in range(2)
        ]
        ids.append(
            store.save_decision(
                "alice",
                farm.id,
                {
                    "engine_version": ENGINE_VERSION,
                    "result": {
                        "status": "success",
                        "data": {
                            "software_test_only": False,
                            "context": {"scenarios": [{"plans": plans}], "sources": []},
                            "summaries": [
                                {
                                    "scenario_id": "fixture",
                                    "status": "insufficient_information",
                                }
                            ],
                            "findings": [
                                {
                                    "scenario_id": "fixture",
                                    "source_ids": [],
                                    "explanation": f"Original retained fixture finding {i}; no reviewed crop rule.",
                                }
                            ],
                        },
                    },
                },
            )
        )
    Comparisons(store).save(
        "alice",
        farm.id,
        ComparisonInput(
            id=uuid4(),
            name="Synthetic farmer-declared comparison",
            exploration_reason="Test all three saved strategies",
            baseline_decision_id=ids[0],
            alternative_decision_ids=ids[1:],
            baseline_declared_existing_plan=True,
        ),
    )
    for i in range(3):
        Journal(store).save(
            "alice",
            farm.id,
            JournalInput(
                id=uuid4(),
                kind="observation",
                occurred_on="2024-01-01",
                notes=f"Synthetic newer note {i}",
            ),
        )
    context = assistant_context(store, "alice", farm.id)
    response = explain(
        ChatRequest(
            question="Explain my crop rotation and saved comparison", context=context
        )
    )
    assert len(response.decisions) == 3
    assert [d.explanation for d in response.decisions] == [
        f"Original retained fixture finding {i}; no reviewed crop rule."
        for i in range(3)
    ]
    text = " ".join(c.text for c in response.claims)
    for role in [
        "Baseline: farmer-declared existing plan",
        "Alternative A: proposed strategy",
        "Alternative B: proposed strategy",
    ]:
        assert role in text
    assert "software-test-crop-2-1" in text
    assert "not recommended crop durations" in text
    assert all(
        e.kind == "farmer_reported" and e.quality == "unverified"
        for e in response.evidence
    )
