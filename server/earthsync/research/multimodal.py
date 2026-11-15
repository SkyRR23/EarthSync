"""Vision -> existing FTS5 -> deterministic, source-linked farmer explanation."""

import time

from .retrieval import EvidenceQuery
from .soil import PHOTO_LIMITATIONS, analyze_photo, parse_lab_text
from .storage import ResearchError
from .vision import LabTranscription, ProviderFailure, VisionExtraction

CROP_LIMITATIONS = [
    "Possible causes to investigate are not a confirmed diagnosis.",
    "One photograph cannot distinguish nutrient, pest, fungal, bacterial, viral, drought, waterlogging, aging or mechanical causes.",
    "No disease probability, chemical measurement, crop ranking, treatment dose or official weather warning is generated.",
    "User-provided crop identity and model-visible features are unverified and may disagree.",
]


def image_analysis(
    photo_id, pixels, *, value, index, provider=None, saved_context=None
):
    # Preserve the exact legacy v1 soil contract when image_kind is absent.
    if value.image_kind is None:
        return analyze_photo(
            photo_id,
            pixels,
            provider=provider if hasattr(provider, "describe") else None,
            consent=value.external_image_consent,
        )
    result = {
        "photo_id": str(photo_id),
        "schema_version": "earthsync.image-evidence.v1",
        "image_kind": value.image_kind,
        "status": "vision_unavailable",
        "provider_status": "vision_unavailable",
        "provider": None,
        "model": None,
        "observations": [],
        "inconclusive": True,
        "human_confirmed": False,
        "chemical_measurements_available": False,
        "measurements": [],
        "recommendation_eligible": False,
        "executable_rules": [],
        "ranking": None,
        "possible_explanations": [],
        "sources": [],
        "citations": [],
        "rag_source_ids": [],
        "limitations": CROP_LIMITATIONS
        if value.image_kind == "crop"
        else PHOTO_LIMITATIONS,
        "missing_information": [
            "Confirm crop identity, growth stage and affected plant distribution.",
            "Record dated symptoms, weather and management history.",
        ],
        "follow_up": [
            "Take a clear close-up and a whole-plant or wider field photo.",
            "Seek local agricultural extension review if symptoms persist or spread.",
        ],
        "crop_context": {
            "provided": value.crop or None,
            "provenance": "farmer_reported",
            "verified_by_image": False,
        },
        "farmer_context": value.model_dump(
            exclude={"external_image_consent", "image_kind"}
        ),
        "saved_environmental_evidence": saved_context
        or {"status": "unavailable: no verified farm linkage"},
        "external_transfer": False,
    }
    if (
        provider is None
        or not getattr(provider, "supports_images", False)
        or not hasattr(provider, "extract")
    ):
        return result
    if provider.external and not value.external_image_consent:
        raise ResearchError("EXTERNAL_IMAGE_CONSENT_REQUIRED", 422)
    started = time.monotonic()
    result.update(
        provider=provider.name,
        model=provider.model,
        external_transfer=provider.external,
    )
    try:
        output = VisionExtraction.model_validate(
            provider.extract(pixels, VisionExtraction)
        )
    except ProviderFailure as exc:
        return {
            **result,
            "provider_status": exc.status,
            "latency_ms": round((time.monotonic() - started) * 1000),
        }
    except Exception:
        return {**result, "provider_status": "invalid_output"}
    result.update(
        provider_status="succeeded",
        latency_ms=round((time.monotonic() - started) * 1000),
    )
    if output.image_type != value.image_kind:
        return {
            **result,
            "status": "image_kind_mismatch",
            "detected_image_type": output.image_type,
        }
    result.update(
        status="unverified_model_observation",
        **output.model_dump(exclude={"limitations"}),
    )
    result["limitations"] = [
        *result["limitations"],
        *["Image limitation: " + s.replace("_", " ") for s in output.limitations],
    ]
    # Only visible findings can select possible explanations. Uncertain findings
    # and inconclusive images cannot be promoted into a cause.
    features = (
        [o.feature for o in output.observations if o.visibility == "visible"]
        if not output.inconclusive
        else []
    )
    evidence = index.retrieve_health(
        image_kind=value.image_kind,
        crop=value.crop,
        features=features,
        region=value.region,
    )
    result["health_evidence"] = evidence
    result["sources"], result["citations"] = evidence["sources"], evidence["citations"]
    result["rag_source_ids"] = [s["id"] for s in result["sources"]]
    result["possible_explanations"] = [
        {
            "claim_id": c["id"],
            "source_id": c["source_id"],
            "reference_says": c["claim"],
            "possibilities": c["possible_explanations"],
            "limitations": c["limitations"],
        }
        for c in evidence["claims"]
    ]
    result["follow_up"] += list(
        dict.fromkeys(s for c in evidence["claims"] for s in c["follow_up"])
    )
    if not evidence["claims"]:
        result["limitations"] += [
            "No vetted plant-health reference matches these visible features, crop and requested scope. No cause is inferred."
        ]
    # Original crop requirements are a clearly separate reference packet. A pH
    # requirement here is never represented as a photographic measurement.
    result["crop_reference"] = (
        index.retrieve(
            EvidenceQuery(
                crop=value.crop, question=value.question, region=value.region, limit=5
            )
        )
        if value.crop
        else None
    )
    return scientific_gate(result, index)


def scientific_gate(result, index):
    """Allowlisted extraction + exact dossier equality; no generated agronomy."""
    if (
        result["measurements"]
        or result["recommendation_eligible"]
        or result["human_confirmed"]
        or result["executable_rules"]
        or result["ranking"] is not None
    ):
        raise ValueError("Scientific policy violation")
    evidence = result["health_evidence"]
    if any(c != index.health_records.get(c["id"]) for c in evidence["claims"]):
        raise ValueError("Altered evidence")
    expected = [
        {"claim_id": c["id"], "source_id": c["source_id"], "locator": c["locator"]}
        for c in evidence["claims"]
    ]
    if result["citations"] != expected:
        raise ValueError("Unretrieved citation")
    if result["sources"] != [
        index.health_sources[s]
        for s in sorted({c["source_id"] for c in evidence["claims"]})
    ]:
        raise ValueError("Altered source")
    explanations = [
        {
            "claim_id": c["id"],
            "source_id": c["source_id"],
            "reference_says": c["claim"],
            "possibilities": c["possible_explanations"],
            "limitations": c["limitations"],
        }
        for c in evidence["claims"]
    ]
    if result["possible_explanations"] != explanations:
        raise ValueError("Unsupported explanation")
    return result


def extract_report(pixels, *, ocr, value, provider=None):
    """Local first, with optional separately retained AI assistance. No auto-confirm."""
    original = ocr.extract(pixels)
    if not value.request_ai_assistance:
        return original
    if not value.external_image_consent:
        raise ResearchError("EXTERNAL_IMAGE_CONSENT_REQUIRED", 422)
    assistance = {
        "status": "vision_unavailable",
        "provider": None,
        "model": None,
        "values": [],
        "confirmation_required": True,
    }
    if (
        provider is not None
        and getattr(provider, "supports_images", False)
        and hasattr(provider, "extract")
    ):
        assistance.update(provider=provider.name, model=provider.model)
        try:
            text = LabTranscription.model_validate(
                provider.extract(pixels, LabTranscription)
            ).transcription
            assistance = {
                **parse_lab_text(text),
                "provider": provider.name,
                "model": provider.model,
                "provenance": "unverified_ai_document_transcription",
            }
        except ProviderFailure as exc:
            assistance["status"] = exc.status
        except Exception:
            assistance["status"] = "invalid_output"
    return {**original, "ai_assistance": assistance}
