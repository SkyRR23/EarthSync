"""Conservative field/date matching and differences of comparable point samples."""

from datetime import timezone

from .models import Photo, SatelliteRecord, TimelineQuery, capture_day
from .satellite import ProviderResult, SatelliteAdapter

LIMITATIONS = [
    "A ground photo cannot locate a farm from its pixels; farm association is farmer-confirmed.",
    "Point-pixel support does not establish whole-field coverage or conditions.",
    "Photo observations are farmer-reported and not scientifically validated.",
    "NDVI change is not a disease diagnosis; radar change is not a soil-moisture or flood estimate.",
    "No interpolation, daily coverage assumption, forecast or crop recommendation is produced.",
]


def mismatch(record: SatelliteRecord, query: TimelineQuery, modality: str):
    if record.modality != modality:
        return "modality_mismatch"
    if record.field != query.field:
        return "confirmed_field_mismatch"
    if (
        not query.start
        <= record.acquired_at.astimezone(timezone.utc).date()
        <= query.end
    ):
        return "outside_date_interval"
    west, south, east, north = record.pixel_bbox
    point = query.field.point
    if not west <= point.longitude <= east or not south <= point.latitude <= north:
        return "pixel_does_not_cover_confirmed_point"
    return None


def comparison_key(record: SatelliteRecord):
    if record.qa != "usable" or record.value is None or record.geometry_id is None:
        return None
    if record.modality == "radar" and any(
        value is None
        for value in (
            record.relative_orbit,
            record.orbit_direction,
            record.polarization,
            record.incidence_angle_deg,
        )
    ):
        return None
    # Exact equality is deliberately conservative: no guessed angular tolerance,
    # reprojection, optical sensor harmonization or regional-to-field conversion.
    return (
        record.evidence_kind,
        record.product,
        record.product_version,
        record.metric,
        record.units,
        record.platform,
        record.geometry_id,
        record.relative_orbit,
        record.orbit_direction,
        record.polarization,
        record.incidence_angle_deg,
        record.resolution_m,
        record.pixel_bbox,
        record.pixel_count,
        record.qa_method,
    )


async def build_timeline(
    query: TimelineQuery, photos: list[Photo], adapters: list[SatelliteAdapter]
):
    events, undated, providers, rejected, differences = [], [], [], [], []
    records = []
    for photo in photos:
        if not photo.farm or photo.farm.farm_id != query.field.farm_id:
            continue
        day = capture_day(photo)
        event = {"type": "photo", "date": day, "photo": photo}
        if day is None:
            undated.append(event)
        elif query.start <= day <= query.end:
            events.append(event)

    for adapter in adapters:
        try:
            result = ProviderResult.model_validate(await adapter.observe(query))
            if result.provider != adapter.provider:
                raise ValueError("Provider identity mismatch")
        except Exception:
            # Adapter/transport failures cannot become empty successful queries.
            result = ProviderResult(
                provider=adapter.provider,
                status="unavailable",
                reason="provider_error_or_invalid_response",
                source_url=adapter.source_url,
                limitations=["No validated observation response is available."],
            )
        accepted = []
        for record in result.records:
            reason = mismatch(record, query, adapter.modality)
            if reason:
                rejected.append(
                    {
                        "provider": result.provider,
                        "record_id": record.id,
                        "reason": reason,
                    }
                )
            else:
                accepted.append(record)
        providers.append(
            {
                **result.model_dump(exclude={"records"}),
                "matched_count": len(accepted),
                "missing_state": (
                    "unavailable"
                    if result.status == "unavailable"
                    else "no_matching_observations"
                    if not accepted
                    else "observations_only_at_listed_acquisitions"
                ),
                "requested_interval": {"start": query.start, "end": query.end},
            }
        )
        records.extend((result.provider, record) for record in accepted)

    previous = {}
    seen = set()
    for provider, record in sorted(records, key=lambda item: item[1].acquired_at):
        if (provider, record.id) in seen:
            rejected.append(
                {
                    "provider": provider,
                    "record_id": record.id,
                    "reason": "duplicate_record",
                }
            )
            continue
        seen.add((provider, record.id))
        events.append(
            {
                "type": record.modality,
                "date": record.acquired_at.astimezone(timezone.utc).date(),
                "record": record,
            }
        )
        key = comparison_key(record)
        if key is None:
            continue
        key = (provider, key)
        earlier = previous.get(key)
        if earlier and earlier.acquired_at < record.acquired_at:
            differences.append(
                {
                    "provider": provider,
                    "from_id": earlier.id,
                    "to_id": record.id,
                    "from_at": earlier.acquired_at,
                    "to_at": record.acquired_at,
                    "metric": record.metric,
                    "units": record.units,
                    "difference": record.value - earlier.value,
                    "evidence_kind": record.evidence_kind,
                    "spatial_support": record.spatial_support,
                    "interpretation": "numeric_difference_only",
                    "qa": "usable",
                    "missing_state": "only_two_listed_acquisitions_compared_no_interpolation",
                    "provenance": {
                        "from_source_url": earlier.source_url,
                        "to_source_url": record.source_url,
                        "product": record.product,
                        "product_version": record.product_version,
                        "qa_method": record.qa_method,
                        "geometry_id": record.geometry_id,
                    },
                    "limitations": list(
                        dict.fromkeys(earlier.limitations + record.limitations)
                    ),
                }
            )
        previous[key] = record

    return {
        "schema_version": "evidence.v1",
        "query": query,
        "events": sorted(events, key=lambda event: event["date"]),
        "undated_photos": undated,
        "providers": providers,
        "rejected_records": rejected,
        "differences": differences,
        "limitations": LIMITATIONS,
    }
