"""Deterministic retrieval only: no network, model, tools, history, or actions."""

import json
import re
from functools import lru_cache
from importlib.resources import files

from .models import ChatRequest, ChatResponse, Claim

# Agricultural content and translations live in locales; these are routing terms.
INTENTS = (
    ("limitations", r"limit|uncertain|reliab|confiden|segur"),
    ("soil", r"soil|suelo|\bph\b|salinity"),
    (
        "satellite",
        r"satellite|satelital|vegetation|vegetaci|radar|ndvi|photo|foto|disease|enfermedad",
    ),
    ("rainfall", r"rain|lluvia|precip|graph|gr[aá]fico"),
    ("crops", r"crop|cultiv|recommend|recomend|planting advice"),
    ("next", r"next|provide|aportar|informaci[oó]n.*debo|siguiente"),
    (
        "area",
        r"area|[aá]rea|zona|happening|condici|temperature|temperatura|climate|clima|weather",
    ),
)
TOPICS = {
    "soil": {"soil"},
    "satellite": {"vegetation", "radar", "photo"},
    "rainfall": {"rainfall"},
    "area": {"climate", "rainfall", "temperature"},
    "next": {"farmer_input"},
    "crops": set(),
    "limitations": set(),
    "fallback": set(),
}
# An unrecognized metric or free text is never promoted into a scientific claim.
METRICS = {
    ("rainfall", "rainfall_total", "mm"),
    ("temperature", "mean_temperature", "deg_c"),
    ("soil", "ph", "pH"),
    ("soil", "organic_carbon", "g/kg"),
    ("soil", "moisture", "volumetric_fraction"),
    ("soil", "moisture", "volumetric_percent"),
    ("vegetation", "ndvi", "1"),
    ("radar", "backscatter", "dB"),
}


@lru_cache(maxsize=2)
def catalog(language):
    return json.loads(
        files(__package__).joinpath(f"locales/{language}.json").read_text()
    )


def resolve_intent(question):
    normalized = question.casefold()
    for name, pattern in INTENTS:
        if re.search(pattern, normalized):
            return name
    return "fallback"


def _reason(record, context, sources, conflicts):
    if record.kind == "synthetic":
        return "synthetic"
    if record.quality != "available" or record.kind == "unavailable":
        return "quality"
    if record.id in conflicts:
        return "conflict"
    if record.kind == "farmer_reported":
        # These records are preserved as reports, never upgraded to measurements.
        return "text"
    if not record.source_ids or any(
        source not in sources or sources[source].url is None
        for source in record.source_ids
    ):
        return "source"
    if (
        record.value is None
        or not record.start_date
        or not record.end_date
        or not record.spatial_support
    ):
        return "metadata"
    if record.scope == "field":
        if (
            not context.confirmed_farm
            or record.location_id != context.confirmed_farm.id
        ):
            return "location"
    elif record.scope == "regional":
        selections = [context.selected_area, context.confirmed_farm]
        if not any(s and s.id == record.location_id for s in selections):
            return "location"
    else:
        return "location"
    if (
        not isinstance(record.value, float)
        or (record.topic, record.metric, record.unit) not in METRICS
    ):
        return "text"
    return None


def _conflicts(records):
    groups = {}
    for record in records:
        # Never compare/fuse different units, dates, kinds or spatial support.
        key = (
            record.topic,
            record.metric,
            record.unit,
            record.start_date,
            record.end_date,
            record.kind,
            record.scope,
            record.location_id,
            record.spatial_support,
        )
        if record.value is not None and record.quality in {
            "available",
            "contradictory",
        }:
            groups.setdefault(key, []).append(record)
    return {
        record.id
        for group in groups.values()
        if len({record.value for record in group}) > 1
        for record in group
    }


def explain(request: ChatRequest) -> ChatResponse:
    context = request.context
    words = catalog(request.language)
    intent = resolve_intent(request.question)
    scope = (
        "farm"
        if context.confirmed_farm
        else "area"
        if context.selected_area
        else "approximate"
        if context.approximate_location
        else "none"
    )
    claims = [Claim(category="general_knowledge", text=words[f"scope_{scope}"])]
    claims.append(Claim(category="general_knowledge", text=words[intent]))
    sources = {source.id: source for source in context.sources}
    wanted = TOPICS[intent]
    if intent == "limitations":
        wanted = set().union(*TOPICS.values())
    relevant = [record for record in context.evidence if record.topic in wanted]
    conflicts = _conflicts(relevant)
    warnings = []
    visible = relevant if request.expanded else relevant[:2]
    for record in visible:
        reason = _reason(record, context, sources, conflicts)
        refs = [ref for ref in record.source_ids if ref in sources]
        if reason:
            message = words["reasons"][reason]
            claims.append(
                Claim(
                    category="unavailable_evidence",
                    text=words["unusable"].format(id=record.id, reason=message),
                    evidence_ids=[record.id],
                    source_ids=refs,
                )
            )
            warnings.append(f"{record.id}:{reason}")
        else:
            claims.append(
                Claim(
                    category="deterministic_calculation"
                    if record.calculation == "rust"
                    else "retrieved_fact",
                    text=words["evidence"].format(
                        topic=record.topic,
                        metric=words["metric_names"][record.metric],
                        value=f"{record.value:g}",
                        unit=record.unit,
                        kind=record.kind,
                        quality=record.quality,
                        start=record.start_date,
                        end=record.end_date,
                        scope=record.scope,
                        # Original spatial-support text appears only in labeled details.
                        support=record.scope,
                    ),
                    evidence_ids=[record.id],
                    source_ids=refs,
                )
            )
    # Contradictions outside the short view must still be surfaced.
    for record_id in sorted(conflicts):
        warning = f"{record_id}:conflict"
        if warning not in warnings:
            warnings.append(warning)
    if conflicts:
        claims.append(
            Claim(category="unavailable_evidence", text=words["reasons"]["conflict"])
        )
    if not relevant and intent not in {"crops", "next", "fallback"}:
        claims.append(Claim(category="unavailable_evidence", text=words["none"]))
    selected_decisions = context.decisions if intent in {"crops", "limitations"} else []
    decisions = selected_decisions if request.expanded else selected_decisions[:2]
    for decision in decisions:
        refs = [ref for ref in decision.source_ids if ref in sources]
        claims.append(
            Claim(
                category="deterministic_calculation",
                text=words[
                    "synthetic_decision" if decision.synthetic else "decision"
                ].format(
                    scenario=decision.scenario_id,
                    status=decision.status,
                ),
                evidence_ids=decision.evidence_ids,
                source_ids=refs,
            )
        )
        unverified = (
            not refs
            or len(refs) != len(decision.source_ids)
            or any(sources[ref].url is None for ref in refs)
        )
        if unverified:
            warnings.append(f"{decision.id}:source")
        if any(
            eid not in {e.id for e in context.evidence} for eid in decision.evidence_ids
        ):
            warnings.append(f"{decision.id}:missing_evidence")
            unverified = True
        if unverified:
            claims.append(
                Claim(
                    category="unavailable_evidence", text=words["decision_unverified"]
                )
            )
    if intent == "crops" and not decisions:
        claims.append(
            Claim(category="unavailable_evidence", text=words["decision_none"])
        )
    if len(visible) < len(relevant) or len(decisions) < len(selected_decisions):
        claims.append(Claim(category="general_knowledge", text=words["more"]))
    if request.expanded:
        claims.append(Claim(category="general_knowledge", text=words["detail"]))
    source_ids = {ref for claim in claims for ref in claim.source_ids}
    # Keep evidence used by decisions too, so every resolvable citation maps back.
    evidence_ids = {eid for claim in claims for eid in claim.evidence_ids}
    return ChatResponse(
        context_id=context.context_id,
        language=request.language,
        intent=intent,
        claims=claims,
        citations=[s for s in context.sources if s.id in source_ids],
        evidence=[e for e in context.evidence if e.id in evidence_ids],
        decisions=decisions,
        limitations=context.limitations,
        warnings=warnings,
        suggested_questions=words["suggestions"],
    )
