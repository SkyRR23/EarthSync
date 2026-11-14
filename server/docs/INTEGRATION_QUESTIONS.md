# Owner decisions before shared-contract approval

This branch's committed server/docs and mocked fixture are the review artifacts.
Other chats must fetch the branch; uncommitted files in this worktree are not a
coordination mechanism. Nothing here approves Rust v0.2 or a Flutter bridge.

Rust owner:

1. Accept unchanged SeasonalRequest/EnvironmentInput extraction plus mandatory
   retained provenance sidecar, or propose a versioned evidence-reference field?
2. How should a durable evidence ID bind point/window, retrieval versions, source
   header and Rust results so stale climate cannot be attached to a different field?
3. Approve POWER modeled classification, LST calendar, full daily coverage and total
   precipitation-to-`rainfall_mm` mapping after live source documentation review?
4. Current v0.1 requires one homogeneous source. How should future SMAP, SoilGrids
   and forecasts retain separate support, uncertainty, data kind and timestamps?

Flutter owner:

1. Who fetches/caches the HTTP response, retains the sidecar and calls the actual
   approved FRB function? No new bridge names are assumed here.
2. Confirm explicit inclusive years/months, exact query-point association, null
   versus zero display, modeled grid-support notice, source/retrieval date display,
   cache freshness and transport-error versus incomplete-evidence states.
3. Confirm cancellation, loading/retry UX, API base URL, deployment/CORS/auth policy;
   no permissive CORS or public deployment is enabled by this P0.

Future providers implement the ClimateProvider protocol only when they can supply
comparable dated monthly climate. SMAP soil moisture, SoilGrids soil properties,
crop references and advisories need separate domain contracts rather than forced
climate fields. No fake providers, soil defaults, drought/heat thresholds or crop
suitability calculations are implemented.

## Review of Rust v0.2 at 1ba6fb08249a95436487575c0ef26ecf8a93df11

Read `docs/ENGINE_CONTRACT_v0.2.md`, `engine/src/v02/mod.rs` and the unchanged
`engine/src/seasonal.rs` from `feat/rust-engine-v0-2` via Git objects; did not merge
or edit that branch. The backend's current SeasonalRequest remains compatible.
Live NASA normalization is now verified (see NASA_POWER.md), but v0.2 adoption
still needs explicit approval. Proposed concrete decisions:

1. **Reference registry:** add a context-only NASA citation to
   `integration.crop_references.sources`, e.g. ID `nasa-power-merra2-daily`,
   `status: reference_only`, scope describing grid/time/methodology limits.
   Use that ID in v0.2 `environmental_provenance.source_refs`; arbitrary sidecar
   IDs alone fail `validate_refs`. Never promote this climate citation to
   `verified_for_supplied_context` for Myanmar crop constraints. Registry placement
   does not turn climate evidence into crop-reference evidence. Approve ID namespace
   and whether a separate environmental registry is needed in a future schema.
2. **Loss-aware provenance:** propose `kind: modeled`, `provider: NASA POWER`,
   `dataset: POWER daily meteorology / MERRA-2`, `observed_on: null` (an interval
   must not be collapsed to one observation date), `retrieved_on` from the UTC
   retrieval date. Keep `spatial_resolution_m: null`; anisotropic angular grid
   support cannot honestly become one scalar meter resolution without a method.
   Put grid, coverage and representativeness caveats in uncertainty text and retain
   the full backend sidecar. The Rust provenance type lacks interval/time standard,
   timestamp precision and per-variable records. Approve this null/date policy.
3. **Evidence binding:** approve canonical serialization/hash or immutable evidence
   ID binding coordinates, window, response values, API/source versions and retrieval
   timestamp to the sidecar. Current JSON has no durable evidence ID; Flutter must
   retain the whole envelope alongside the derived Rust request/result until that
   mechanism exists. Do not claim cryptographic linkage has been implemented.
4. **Homogeneous product and dates:** approve MERRA-2-only P0 and safe rejection of
   GEOS-IT/mixed lineage. Approve inclusive full LST months (not device civil dates),
   `mm/day × 1 day` sums, full-daily-mean T2M aggregation, independent nulls, and
   exact representative-point association. No temperature/water suitability rule
   is authorized by agreement on these climate statistics.
5. **Flutter boundary:** choose opt-in v0.2 wrapper/decoder and HTTP ownership,
   preserving current legacy flow. Flutter must send the selected field point,
   preserve scenario order and nullable IDs, display modeled/forecast distinctly,
   retain sidecar/retrieval dates, and distinguish 502/503 from valid incomplete
   evidence. Do not reuse synthetic demo coordinates or label supplied_data as a
   verified agronomic outcome. FRB generation and Android device tests remain P4 work.

These are proposals for Rust/Flutter owner approval, not unilateral shared-contract
changes. P0 supplies no reviewed crop constraints, soil/history defaults or schedules.
