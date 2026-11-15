# Standalone API v1

Base: `http://127.0.0.1:8021/api/platform/v1`.
Interactive documentation: `http://127.0.0.1:8021/docs`.
Actual OpenAPI: `http://127.0.0.1:8021/openapi.json`.

Startup requires explicit local-single-user mode. All routes, including OpenAPI,
reject non-loopback peers, untrusted Host headers and browser origins. No hosted
identity protocol is invented. Do not expose the service through a reverse proxy.
No caller-controlled owner ID, provider URL, executable, file path or raw engine
request is accepted. Existing NASA/environmental/photo/chat routes are unchanged.

| Method | Path suffix | Behavior |
|---|---|---|
| GET | `/health` | Local liveness, no provider probes |
| GET | `/ready` | Storage integrity + actual startup Rust probe, 503 if unavailable |
| GET | `/providers` | Dated last source attempts, no implicit live calls |
| POST/GET | `/farms` | Explicit confirmed farm creation/list, owner from server |
| GET | `/farms/{id}` | Confirmed point/polygon/system, distinct from area |
| GET | `/farms/{id}/context` | Owned farm, stored evidence and reported history |
| POST/GET | `/farms/{id}/history` | Farmer-reported historical crop/fallow records |
| GET | `/farms/{id}/assistant-context` | PR #14 typed source-grounded context projection |
| POST | `/climate/jobs` | Regional request with optional confirmed-farm association |
| POST | `/soil/jobs` | Focused reference-only pH WCS probe, explicit failed access |
| POST | `/optical/jobs` | Confirmed-point HLS metadata candidates, not numerical imagery |
| GET/DELETE | `/jobs/{id}` | Owner-scoped status / best-effort cancellation |
| GET | `/evidence/{id}` | Full immutable versioned source evidence sidecar |
| GET | `/catalog/{profile_id}` | Exact installed reference catalog, eligibility false |
| POST | `/assessments` | Server-built attributable request to actual Rust v0.3 |
| GET | `/farms/{id}/decisions` | Authorized assessment history |
| POST/GET | `/farms/{id}/photos` | Raw JPEG/PNG upload/list, reuses #16 sanitizer |
| GET | `/farms/{id}/photos/{photo_id}/image` | Owned sanitized PNG, no EXIF retained |
| DELETE | `/farms/{id}/photos/{photo_id}` | Remove authorized metadata/file reference |

Photos require PR #16's installed sanitizer (assembled image includes it). Upload
body is the image, `Content-Type: image/jpeg` or `image/png`; no multipart/path/URL
or EXIF-GPS ownership inference. JSON cap is 2 MB; image cap 10 MiB; the reused
sanitizer caps pixel count/dimensions/animation. Private responses use no-store.
Two decoders and eight admitted requests bound working memory. Uvicorn must run
one worker with the provided external concurrency limit; it also bounds waiting
HTTP tasks. Local throttle is 120 requests/minute for the single demo principal.

Example farm (sample geometry for software testing only):

```json
{"name":"Software test regional point; no farm ground truth","confirmed_point":{"latitude":42.03,"longitude":-93.62},"confirmed_on":"2026-11-14","production_system":"rainfed"}
```

Climate job (omit `farm_id` for regional context without a farm):

```json
{"farm_id":"REPLACE_WITH_CONFIRMED_FARM_UUID","query":{"point":{"latitude":42.03,"longitude":-93.62},"start":"2024-02-01","end":"2024-02-29","lineage":"MERRA2","contract_version":"power-daily-merra2.v1"}}
```

Assessment after persisting evidence associated with that exact owned farm:

```json
{"farm_id":"REPLACE_WITH_CONFIRMED_FARM_UUID","evidence_ids":["REPLACE_WITH_STORED_EVIDENCE_ID"],"pilot_id":"us_ia_story","profile_ids":["us_ia_story_corn_rainfed_v1"],"start":"2024-02-01","end":"2024-02-29"}
```

`profile_ids` represent separate alternatives. To assert sequential use explicitly,
use `plans:[{profile_id,start,end},...]` with `sequential_field:true` instead. The
actual engine can identify overlapping dates without approved crop thresholds;
this is a calendar conflict, not a finding that either crop is suitable. Planting
calendars are caller proposals, not automatic date recommendations. No reviewed
requirements means useful gaps and insufficient-information results.

Jobs return 202 with an ID. Statuses: queued/running/succeeded/failed/cancelled.
`succeeded` means the operation completed and may contain source-specific gaps;
inspect `records` and `gaps`. Access failures in soil/discovery set failed status
with the precise safe code. Provider failures are never replaced by mock data.
Restarted in-flight jobs become retryable failures. Re-submit explicitly for retry;
pending owner/product/version/geometry-identical jobs deduplicate. Cancellation is
best effort and may follow already-authorized evidence writes; private saved
records are never silently discarded or relabeled.

Safe error shape:

```json
{"error":{"code":"OUTBOUND_PROXY_BLOCKED","retryable":false}}
```

- Invalid input: 422 `INVALID_INPUT`; unknown/unowned resource: 404 `NOT_FOUND`.
- Unavailable/missing capability: 503 `CATALOG_NOT_INSTALLED`, `RUST_NOT_CONFIGURED`,
  `PHOTO_SERVICE_NOT_INSTALLED`, `PROVIDER_UNAVAILABLE`, `PROVIDER_ACCESS_DENIED`,
  `OUTBOUND_PROXY_BLOCKED`.
- Network/process deadline: 504 `TIMEOUT` / `RUST_TIMEOUT`.
- Admission/provider rate: 429 `RATE_LIMIT`, `JOB_CAPACITY`,
  `LOCAL_PROVIDER_RATE_LIMIT`.
- Wrong lineage/schema/unit/time/space: 502 provider contract errors or 422 when
  supplied local evidence is incompatible. Missing values remain explicit nulls.
- Scientific rejection: `SCIENTIFIC_QUALITY_REJECTION`; process failure:
  `RUST_EXECUTION_FAILURE`; bad engine response: `RUST_SCHEMA_MISMATCH`.
- Privacy boundary: 403 `LOCAL_ONLY` / `ORIGIN_FORBIDDEN`; a future hosted service
  must separately define 401/session behavior. Do not confuse demo loopback access
  with production authentication.
- Size/quota: 413 `REQUEST_TOO_LARGE`, 507 `STORAGE_QUOTA`.

No numerical radar/forecast-success endpoint is advertised. Existing environmental
and satellite APIs retain unavailable states until their own acceptance is done.
All service numbers stay source-attributed; no arbitrary warnings, crop scores,
yield/profit estimates or emergency thresholds are added.
