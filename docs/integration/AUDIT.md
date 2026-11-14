# EarthSync Milestone 7H integration audit

The isolated branch is `integration/earthsync-milestone-7h`, based on
`origin/feat/web-demo` at `e0cdaaf875efb376e3081a66826b4b5e21601c67`.
[source-manifest.json](source-manifest.json) pins PR descriptions and exact source
heads. Each source head was merged with a separate merge commit. The source PRs
remain untouched; the integration targets `feat/web-demo`, never `main`.

## Compatibility matrix

| Source | Existing boundary | Integration and preserved limitations |
| --- | --- | --- |
| #12 API reliability | POWER `1.0-proposal`, integration/v0.2, diagnostics | Retain timeouts, streamed caps, bounded workers, safe errors and MERRA-2 source guard. Normal launcher uses the same app. |
| #13 onboarding/dashboard | Version-1 local profile, Riverpod state, GoRouter | Primary main application. Optional location/manual/skip, independent confirmed farm, refresh restoration, historical graphs and dated GIBS preview. Add a backward-compatible optional device-location record, separate from manually selected area. |
| #14 assistant | `assistant.v1-proposal` | Router mounted at `/api/assistant/v1/chat`. Main navigation binds current permitted evidence. Extend the additive decision enum to retain all five v0.3 states; regenerate both JSON schemas. No model/key/network retrieval inside assistant. |
| #15 crop knowledge | `earthsync.crop-knowledge.v1-proposal`, catalog 0.1.0 | Validate using producer schema AND source/claim graph validator. Explicit six-profile mapping; reference-only, no executable requirements or candidate approvals. Preserve all original parameters/claims in sidecars. |
| #16 photos/SAR | `evidence.v1`, one token per private workspace | Mount child app at `/api/evidence`, with child prefix `/v1`. Preserve atomic SQLite CRUD, quotas, consent and two-stage sanitization. Main host additionally requires loopback/HTTPS. Native/Web reusable panel is now reachable. HLS/OPERA remain unavailable. |
| #17 environmental | `environmental-context/1.0-proposal` | Main app lifespan owns the shared HTTP client and context service. Exact original context URL mounted. All default soil/weather/vegetation data stay unavailable, no numbers or diagnoses invented. |
| #18 Rust engine | `earthsync.engine.v0.3.0` | Executable `--v03`, HTTP `/api/engine/v03`, immutable versioned Flutter request/result wrappers. Native dispatch over the existing FRB JSON string ABI; no generated signature/hash changes needed. Host FFI tests execute actual v0.3. |

## Shared-file resolution

* `app/pubspec.yaml`: actual conflict. Keep geolocator/shared_preferences from #13
  AND image_picker/exif from #16. Add only bundled font assets afterward.
* `app/pubspec.lock`: actual conflict at minimum Flutter SDK. Preserve union of
  package entries, versions and hashes; select the stricter `>=3.47.0` constraint.
  Flutter 3.50.0 / Dart 3.14.0 successfully resolves with `--enforce-lockfile`,
  without upgrading the merged package pins.
* `server/pyproject.toml`: Git merged cleanly; reviewed both sides. Retain assistant
  locale package data and the evidence extra. Unified install additionally requires
  Pillow and jsonschema; pin their transitives in `requirements.lock`. The old
  evidence extra/lock remains usable as a compatibility installation entrypoint.
* `server/tests/test_web_demo.py`: both sides make the same line-wrapping fix.
  Retain #12's extra process-kill/drain assertions; #16 contributes no lost behavior.
* Combined tests exposed unqualified `conftest` imports in environmental tests.
  Make that test directory a package and use relative imports, so photo fixtures
  cannot replace environmental helpers at runtime.

Tests ran incrementally: API 74, assistant 44, catalog 39, photo 76,
environmental 62, engine 111 and bridge 6. These are component checkpoints, not
additive totals. The final report records complete combined counts.

## Catalog-to-engine decisions

Versioned engine IDs are `<catalog-id>@catalog-0.1.0` (and likewise crop IDs).
Cultivar nulls and sourced family strings are retained. Explicit system mappings:

| Catalog production system | Engine system |
| --- | --- |
| rainfed_upland | rainfed |
| dryland_winter_cereal / dryland_summer_cereal | dryland |
| irrigated_flooded_lowland | flooded_lowland |
| irrigated_upland | irrigated |
| irrigated_drill_sown_delayed_flood | Blocked: no agreed equivalent |
| dryland_fallow | Blocked as crop profile: fallow is management/history |

Desk-reviewed facts do not become `reviewed` agricultural engine rules.
`recommendation_eligible: false` maps to `approved_for_candidates: false` and
`review: reference_only`. No advisory planting window becomes a hard rule, soil
establishment temperature becomes daily air limits, annual statistic becomes
crop-period rainfall, generic coefficient becomes stage Kc, or unknown depth/date
becomes a guessed value. There is currently **no compatible numerical requirement**
in this reference catalog. Mapped profiles therefore contain empty rule lists;
actual Rust emits `catalog.rules` / `insufficient_information`. That is the useful
result supported by these records, not an incomplete positive recommendation.

The handoff preserves the complete profile, per-parameter units, statistics,
review metadata, claim IDs, original source graph, partial date precision, scope,
nulls and missing reasons. Sources supplied to Rust remain reference-only. Original
records remain visible in the UI and adapter response. A named pilot is selected
as a research scope; coordinates do not establish regional applicability.

## Integration fixes beyond merging

Main-app routes now expose field situation, photos, assessments and assistant.
API paths are reserved before static hosting; unknown APIs return JSON errors.
Farm/date revisions discard stale analysis callbacks and assistant replies.
Changing an area does not change a farm. Photo GPS never supplies farm confirmation.

Browser testing found a blank startup due to renderer CDN requests, inaccessible
chart text, unsupported Web image-descriptor getters, and a question-draft race
while evidence arrived. Fixes self-host the renderer/font, separate chart semantics
from dated text, preflight JPEG/PNG dimensions without unsupported Web getters,
and preserve unsent questions during evidence-only refreshes. Regression tests and
browser acceptance cover these paths. No error is hidden by substituting fixtures.
