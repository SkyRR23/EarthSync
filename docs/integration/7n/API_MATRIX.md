# 7N API usage and compatibility audit

Generated from actual FastAPI OpenAPI, including the separately mounted photo app. Reproduce with `PYTHONPATH=server python scripts/audit_final_api.py docs/integration/7n/evidence/api`. Full schemas/parameters/responses and operation IDs are committed beside this matrix. All 53 operations below were enumerated; six are the intentional unknown-API fallback. Framework docs/static routes are not product APIs.

Security boundaries: **A** = existing local/demo application (no production identity; bind loopback in trusted staging). **W** = workspace bearer capability plus secure-transport/loopback checks; session-only Flutter token. **P** = explicitly enabled single-user service, loopback peer + Host + exact Origin checks and server-selected owner on every operation. P routes are never mounted on A. OpenAPI descriptions do not replace these runtime checks.

`untyped` below means the source OpenAPI exposes an empty success schema. The raw contract is exercised by typed Dart decoders/integration tests but is not claimed to be fully generated/type-complete. This remains a documented API-maintenance limitation.

| Method / endpoint | Consumer / purpose | Boundary | Request → response schema | Errors / states | Integration evidence |
|---|---|---|---|---|---|
| `POST /api/v1/diagnostics/nasa` | Launcher diagnostics; internal opt-in | A | none/query:  → 200 untyped | 400/403/502/503/504 | reliability/test_backend |
| `GET /api/v1/health` | Launcher/readiness; used | A | none/query:  → 200 untyped | 503 | test_backend.py; test_reliability.py |
| `GET /api/v1/environment/season` | NasaPowerClient, ClimatePanel, questionnaire; used | A | none/query: latitude, longitude, start_year, start_month, end_year, end_month → 200 SeasonResponse | 400/422/502/503/504 | test_backend.py; test_reliability.py; test_system_integration.py |
| `POST /api/assistant/v1/chat` | HttpAssistantService; deterministic explanations; used | A | ChatRequest → 200 ChatResponse | 400/413/422/429 | assistant/test_assistant.py; test_system_integration.py |
| `GET /api/demo/capabilities` | PhotosScreen detects private workspace; used | A | none/query:  → 200 untyped | service outage | test_system_integration.py |
| `POST /api/environmental/v1/context` | environmentalProvider and EnvironmentalPanel; used | A | ContextQuery-Input → 200 ContextResponse | 422/502/503/504 | environmental/; test_system_integration.py |
| `GET /api/environmental/v1/health` | Launcher/operations; intentionally internal | A | none/query:  → 200 untyped | service outage | environmental/; test_system_integration.py |
| `POST /api/satellite/v1/timeline` | satelliteProvider without workspace; used | A | TimelineQuery → 200 untyped | 422; unavailable/rejected source states in 200 | evidence/test_satellite.py; test_system_integration.py |
| `POST /api/v1/diagnostics/integration` | Launcher opt-in diagnostics; internal | A | none/query:  → 200 untyped | 403/422/502/504 | test_reliability.py; test_web_demo.py |
| `GET /api/demo/captured-climate` | Explicit captured software demonstration only | A | none/query:  → 200 untyped | fixture unavailable; never live fallback | test_web_demo.py; test_system_integration.py |
| `GET /api/demo/synthetic-v02` | Legacy v0.2 compatibility demo; intentionally retained | A | none/query:  → 200 untyped | fixture unavailable; labeled synthetic | test_web_demo.py |
| `GET /api/demo/synthetic-v03` | AssessmentNotifier explicit synthetic action; used | A | none/query:  → 200 untyped | fixture unavailable; labeled synthetic | test_system_integration.py |
| `POST /api/engine/{version}` | V03Engine on Web; integration/v02 legacy consumers retained | A | object → 200 untyped | 404/413/422/502/503/504; Rust validation envelope retained | test_web_demo.py; test_system_integration.py |
| `GET /api/catalog/v1/profiles` | catalogProvider, Sources, assessment and history; used | A | none/query:  → 200 untyped | 503/500 catalog integrity | test_system_integration.py; data/crop-knowledge/v1/tests |
| `POST /api/catalog/v1/assessment-request` | AssessmentNotifier reference projection; used | A | AssessmentQuery → 200 untyped | 404/422/503; unsupported mapping blockers | test_system_integration.py |
| `POST /api/{path}` | Intentional unknown API fallback; no feature consumer | A | none/query: path → 200 untyped | 404 UNKNOWN_API; never serves HTML | test_system_integration.py |
| `PUT /api/{path}` | Intentional unknown API fallback; no feature consumer | A | none/query: path → 200 untyped | 404 UNKNOWN_API; never serves HTML | test_system_integration.py |
| `DELETE /api/{path}` | Intentional unknown API fallback; no feature consumer | A | none/query: path → 200 untyped | 404 UNKNOWN_API; never serves HTML | test_system_integration.py |
| `GET /api/{path}` | Intentional unknown API fallback; no feature consumer | A | none/query: path → 200 untyped | 404 UNKNOWN_API; never serves HTML | test_system_integration.py |
| `OPTIONS /api/{path}` | Intentional unknown API fallback; no feature consumer | A | none/query: path → 200 untyped | 404 UNKNOWN_API; never serves HTML | test_system_integration.py |
| `PATCH /api/{path}` | Intentional unknown API fallback; no feature consumer | A | none/query: path → 200 untyped | 404 UNKNOWN_API; never serves HTML | test_system_integration.py |
| `GET /api/evidence/v1/photos` | HttpPhotoEvidenceRepository / PhotoEvidencePanel; existing private gallery retained | W | none/query:  → 200 list[Photo] | 401/403/404/413/422/507; source unavailable states remain explicit | evidence/test_photos.py; test_system_integration.py |
| `POST /api/evidence/v1/photos` | HttpPhotoEvidenceRepository / PhotoEvidencePanel; existing private gallery retained | W | none/query:  → 201 Photo | 401/403/404/413/422/507; source unavailable states remain explicit | evidence/test_photos.py; test_system_integration.py |
| `PUT /api/evidence/v1/photos/{photo_id}` | HttpPhotoEvidenceRepository / PhotoEvidencePanel; existing private gallery retained | W | none/query: photo_id → 200 Photo | 401/403/404/413/422/507; source unavailable states remain explicit | evidence/test_photos.py; test_system_integration.py |
| `GET /api/evidence/v1/photos/{photo_id}` | HttpPhotoEvidenceRepository / PhotoEvidencePanel; existing private gallery retained | W | none/query: photo_id → 200 Photo | 401/403/404/413/422/507; source unavailable states remain explicit | evidence/test_photos.py; test_system_integration.py |
| `DELETE /api/evidence/v1/photos/{photo_id}` | HttpPhotoEvidenceRepository / PhotoEvidencePanel; existing private gallery retained | W | none/query: photo_id → 204 empty | 401/403/404/413/422/507; source unavailable states remain explicit | evidence/test_photos.py; test_system_integration.py |
| `GET /api/evidence/v1/photos/{photo_id}/image` | HttpPhotoEvidenceRepository / PhotoEvidencePanel; existing private gallery retained | W | none/query: photo_id → 200 untyped | 401/403/404/413/422/507; source unavailable states remain explicit | evidence/test_photos.py; test_system_integration.py |
| `POST /api/evidence/v1/timeline` | HttpPhotoEvidenceRepository / PhotoEvidencePanel; existing private gallery retained | W | none/query:  → 200 untyped | 401/403/404/413/422/507; source unavailable states remain explicit | evidence/test_photos.py; test_system_integration.py |
| `GET /api/platform/v1/health` | Operations liveness; internal | P | none/query:  → 200 untyped | service outage | test_api_engine.py |
| `GET /api/platform/v1/ready` | Local staging/launcher smoke; internal | P | none/query:  → 200 untyped | 503 storage/Rust readiness | test_api_engine.py; test_final_integration.py |
| `GET /api/platform/v1/providers` | Source health diagnostics; internal; no extra UI needed | P | none/query:  → 200 untyped | last source-attempt failure in 200 | test_api_engine.py |
| `GET /api/platform/v1/farms` | Platform operator/archive and legacy API; Flutter uses farm-links to avoid duplicate creation | P | none/query:  → 200 list[Farm] | 422/507 | test_api_engine.py; test_storage_jobs.py |
| `POST /api/platform/v1/farms` | Platform operator/archive and legacy API; Flutter uses farm-links to avoid duplicate creation | P | FarmInput → 201 Farm | 422/507 | test_api_engine.py; test_storage_jobs.py |
| `POST /api/platform/v1/farm-links` | PlatformFarmClient.confirm explicit consent; used | P | FarmLinkInput → 201 untyped | 409 FARM_LINK_CONFLICT; 422; 507 rollback | test_final_integration.py |
| `GET /api/platform/v1/farm-links/{local_profile_id}` | PlatformFarmClient.link read-only restart recovery; used | P | none/query: local_profile_id, revision → 200 untyped | 404 NOT_FOUND; 422 revision | test_final_integration.py |
| `GET /api/platform/v1/farms/{farm_id}` | Operations/direct UUID lookup; context includes same farm for Flutter | P | none/query: farm_id → 200 Farm | 404 NOT_FOUND; 422 UUID | test_api_engine.py |
| `GET /api/platform/v1/farms/{farm_id}/context` | platformContextProvider → persisted farm view; used | P | none/query: farm_id → 200 untyped | 404/422 | test_api_engine.py; test_final_integration.py |
| `GET /api/platform/v1/farms/{farm_id}/assistant-context` | platformAssistantProvider → deterministic assistant; used | P | none/query: farm_id → 200 untyped | 404/422 | test_api_engine.py; test_final_integration.py |
| `POST /api/platform/v1/farms/{farm_id}/history` | POST PlatformFarmClient.history; GET internally supported; Flutter reads history via context | P | HistoryInput → 201 untyped | 404/422/507; historical farmer report only | test_api_engine.py; test_storage_jobs.py; test_final_integration.py |
| `GET /api/platform/v1/farms/{farm_id}/history` | POST PlatformFarmClient.history; GET internally supported; Flutter reads history via context | P | none/query: farm_id → 200 untyped | 404/422/507; historical farmer report only | test_api_engine.py; test_storage_jobs.py; test_final_integration.py |
| `POST /api/platform/v1/climate/jobs` | Existing PlatformClimateClient reused for area/farm requests; used | P | ClimateInput → 202 untyped | 422 SPATIAL_MISMATCH; 429 JOB_CAPACITY; source gaps on completion | test_api_engine.py; test_final_integration.py; test_live_opt_in.py |
| `POST /api/platform/v1/soil/jobs` | Intentionally internal experimental WCS probe; no diagnostic consumer | P | SoilInput → 202 untyped | 422/429; failed job with provider/access/schema code | test_api_engine.py; test_satellite_soil.py |
| `POST /api/platform/v1/optical/jobs` | Intentionally internal HLS discovery; no accepted live pixel consumer | P | OpticalInput → 202 untyped | 404/422/429; failed job with provider/access/schema code | test_api_engine.py; test_satellite_soil.py |
| `GET /api/platform/v1/jobs/{job_id}` | PlatformClimateClient.refresh/poll/cancel; used | P | none/query: job_id → 200 untyped | 404/422; failed/cancelled/restart retryability | test_api_engine.py; test_storage_jobs.py; app/test/ui/platform_integration_test.dart |
| `DELETE /api/platform/v1/jobs/{job_id}` | PlatformClimateClient.refresh/poll/cancel; used | P | none/query: job_id → 200 untyped | 404/422; failed/cancelled/restart retryability | test_api_engine.py; test_storage_jobs.py; app/test/ui/platform_integration_test.dart |
| `GET /api/platform/v1/evidence/{evidence_id}` | Direct lineage inspection; UI receives complete records through farm context/job | P | none/query: evidence_id → 200 Evidence | 404 NOT_FOUND | test_api_engine.py; test_storage_jobs.py |
| `GET /api/platform/v1/catalog/{profile_id}` | Internal compatibility lookup; Flutter uses richer 7H catalog/claim graph | P | none/query: profile_id → 200 untyped | 404/503 catalog unavailable | test_api_engine.py |
| `POST /api/platform/v1/assessments` | PlatformFarmClient.assess → actual Rust → saved decision; used | P | AssessmentInput → 200 untyped | 404/422 validation with exact Rust envelope; 502/503/504/507 | test_api_engine.py; test_final_integration.py |
| `GET /api/platform/v1/farms/{farm_id}/decisions` | platformDecisionsProvider and assistant projection; used | P | none/query: farm_id → 200 untyped | 404/422 | test_api_engine.py; test_final_integration.py |
| `POST /api/platform/v1/farms/{farm_id}/photos` | Intentionally separate farm-owned archive API; no implicit workspace migration/UI switch | P | raw bounded JPEG/PNG (source OpenAPI has no request schema) → 201 untyped | 404/413/422/503/507; sanitized uploads only | test_api_engine.py |
| `GET /api/platform/v1/farms/{farm_id}/photos` | Intentionally separate farm-owned archive API; no implicit workspace migration/UI switch | P | none/query: farm_id → 200 untyped | 404/413/422/503/507; sanitized uploads only | test_api_engine.py |
| `GET /api/platform/v1/farms/{farm_id}/photos/{photo_id}/image` | Authorized local object retrieval; current UI retains workspace gallery | P | none/query: farm_id, photo_id → 200 untyped | 404/422/500 object integrity | test_api_engine.py |
| `DELETE /api/platform/v1/farms/{farm_id}/photos/{photo_id}` | Explicit local object delete, internal archive consumer | P | none/query: farm_id, photo_id → 204 empty | 404/422/500 object integrity | test_api_engine.py |

## Disconnected and duplicate services

- Monthly and daily POWER remain different versioned products. The monthly endpoint and original lineage are unchanged; the 7L daily client now uses the shared local transport, optional verified farm UUID, bounded polling and explicit terminal states. A successful 202 submission is not completion.
- The generic 7H ServiceClient intentionally remains a 200/JSON client for its existing endpoints. The private platform uses endpoint-specific 200/201/202/204 handling; no broad “all 2xx means completed” change was made. Mutations are not automatically replayed.
- Farm records were disconnected from local profile IDs. The new owner/local-ID/confirmation-revision link resolves that gap transactionally and restores through read-only lookup. Crop notes remain local; selected reported periods are explicitly saved as history. There is no inferred production system.
- Platform daily evidence now reaches the farm view, explicit source selection, real Rust assessment persistence and permitted assistant evidence/decisions. Exact source IDs are retained. Repeated snapshots are selectable; no arbitrary retrieval order chooses scientific evidence.
- Both catalog endpoints remain because the 7H endpoint exposes the full citation/claim graph; the platform lookup is its reference-only engine compatibility surface. Neither exports reviewed agricultural rules.
- 7H workspace photos and 7I farm-owned photos have different ownership boundaries. The working workspace gallery remains the UI consumer. Farm-owned routes are tested local archive APIs; no automatic copying or token reuse is enabled. A reviewed consented migration is deferred and described in DATABASE.md.
- WCS soil and HLS discovery have no essential user consumer: live access/quantitative acceptance remains unavailable. No UI was added solely to exercise these APIs. No radar/forecast success route was invented.
- Existing `/api/{path}` fallback creates duplicate operation-ID warnings because it handles six methods. Runtime behavior is covered and unchanged; full OpenAPI exports explicitly retain this documentation limitation.

Coverage references identify tests that exercise the operation or its shared storage/security contract; they do not claim a live provider success or a separate test for every possible status. Live tests and CI results are reported in VERIFICATION.md.

## Scientific boundary acceptance

7J J01–J04 now protect the original monthly endpoint: requested/returned point
association including POWER's measured three-decimal serialization, duplicate JSON
key rejection, exact calendar-window checks and original-byte SHA-256 provenance.
J05 scopes Rust crop/fallow succession history to the confirmed field. J06's separate
7I precision patch is applied with adjacent-point and out-of-domain rejection.
Regressions are in `server/tests/test_science_audit.py`,
`server/tests/platform_v1/test_science_coordinate_precision.py` and
`engine/tests/science_audit.rs`. No route/schema or recommendation eligibility was
silently changed. The API schema exports remain structurally current.
