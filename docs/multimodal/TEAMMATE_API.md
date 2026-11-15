# Compatible research API and secure startup

Reuse [PR #34's credential/startup runbook](../crop-intelligence/TEAMMATE_API.md).
Research tokens remain scoped, expiring, revocable and exact-farm-granted. No new
browser credential or cross-tenant database access is introduced. Only an approved
teammate backend may hold a research token and call the service over verified TLS.
Firebase health is not evidence that these endpoints are installed. No hosted
request, public deployment, prohibited host or teammate credential is used here.

`POST /api/research/v1/photos/{photo_id}/analyze` remains additive. Old payloads
with farm_id and consent retain the legacy soil contract. Explicit image-kind
payloads use the new bounded pipeline:

```json
{
  "farm_id": "REPLACE_WITH_GRANTED_FARM_UUID",
  "image_kind": "crop",
  "crop": "maize",
  "question": "What could explain these yellow patches?",
  "growth_stage": "farmer-reported vegetative",
  "weather_context": "farmer reported recent rain",
  "farmer_symptoms": "yellow patches noticed yesterday",
  "external_image_consent": false
}
```

`image_kind` is `crop` or `soil`; laboratory documents use the separate extraction
endpoint. Optional `region` requires an exact documented reference scope, not a
free-form farm-location match. Responses add provider/model/status, bounded visible
findings, evidence/source IDs and exact citations, limitations, missing information,
safe follow-ups and provenance. No provider returns `vision_unavailable` on new
requests. Legacy omitted-kind requests still return `unavailable`. Mock custom
legacy providers retain the existing `describe` protocol; new adapters use `extract`.

`POST /api/research/v1/lab-reports/extract` accepts optional
`request_ai_assistance` and `external_image_consent` booleans alongside farm/photo
IDs. Default is local-only OCR. AI assistance is nested under `original.ai_assistance`;
`original.transcription` preserves local text and `confirmed` remains separate.
The same extraction/confirmation scopes and farm checks apply. A request for AI
without consent returns 422; an unavailable provider retains OCR plus an unavailable
assistance status. Explicit new fields reject unexpected values. The generated
[OpenAPI](../crop-intelligence/openapi.json) is updated and snapshot-tested.

The local farmer boundary supports the same optional body without farm_id on its
existing `/farms/{farm_id}/photos/{photo_id}/analyze` and `/lab-extraction` routes.
`GET /api/platform/v1/image-capabilities` exposes configured public model metadata
only; never keys. Existing loopback/Origin/ownership boundaries still apply.

## Local Linux

```sh
python -m venv /tmp/earthsync-multimodal-venv
/tmp/earthsync-multimodal-venv/bin/python -m pip install -r server/requirements.lock
export EARTHSYNC_VISION_ENABLED=0
export PYTHONPATH="$PWD/server"
# Build Flutter Web/Rust as in docs/crop-intelligence/VERIFICATION.md first.
/tmp/earthsync-multimodal-venv/bin/python scripts/run_final_local.py --directory /tmp/earthsync-multimodal-private
```

For the independent research API, provision a dedicated test key/farm using the
existing CLI into a new owner-only file outside Git, then start the existing
research `app_factory` on loopback. See the inherited runbook for exact scope and
HTTPS deployment commands. Tesseract must be installed separately for local OCR;
absence returns manual entry, not synthetic values. Keep private state, image bytes,
API keys and backups outside the checkout. Stop writers before backup; existing
backup/restore carries nested AI originals without a migration.
