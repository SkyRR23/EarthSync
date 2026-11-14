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
