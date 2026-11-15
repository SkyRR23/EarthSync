# 7H compatibility and file ownership handoff

7I is based on origin/feat/web-demo at e0cdaaf. All branch/PR refs were fetched
before implementation. PR #10 and PRs #12–#18 were read as actual source. No
published 7H integration branch/draft existed during either initial inspection or
the mid-task recheck. Do not automatically rebase when one appears.

## Exclusive 7I files

- `server/earthsync/platform_v1/**`: new package, no existing module overwritten.
- `server/tests/platform_v1/**`: isolated tests, actual captured-provider fixtures.
- `server/docs/platform_v1/**`: contract schemas, audit, receipts and runbooks.
- `server/platform-v1/**`: separate pinned environment, deployment and tools.
- `.github/workflows/platform-v1.yml`: new dedicated CI only.

No central API/router, shared dependency/lock file, Run-WebDemo.ps1, Flutter file,
Rust interface, generated binding or other developer's worktree is edited.
The draft PR targets `feat/web-demo`; neither 7H nor main is merged or rewritten.

## Audited source pins and integration boundaries

| Existing PR | Inspected head | 7I relationship |
|---|---|---|
| #10 web demo | e0cdaaf | Base, old monthly/engine endpoints unchanged |
| #12 reliability | f28d2a3 | Preserve monthly MERRA2 guard; read GEOSIT proposal; new daily service has separate lineage/version/cache |
| #13 dashboard | e05c537 | No Flutter/router edits; explicit farm point/polygon remains separate from approximate area |
| #14 assistant | db42b96 | Typed assistant-context adapter; actual original explain() tested, no duplicate chat service |
| #15 catalog | c4112d2 | Exact artifact hash; system/identity projection, no rule export or eligibility promotion |
| #16 evidence | d5e24f3 | Reuse sanitizer; new owned farm object refs, existing workspace/blob DB untouched |
| #17 environment | 59f028e | REST soil/weather stay reference-only; new WCS pH path is isolated, not a replacement route |
| #18 Rust v03 | 6f7f810 | Actual v03_demo --stdin executable, exact engine version, retained sidecars; no engine changes |

`prepare_compat.py` exports exact Git artifacts into a **new** private directory.
Tests use those source trees explicitly. Docker assembles them outside all active
worktrees. These are dependencies for verification, not merges or a new reviewed
integration base. If a feature head changes, review the exact diff and rerun
compatibility before changing a pin. Crop catalog system aliases collapse only
into existing engine enums; original system/review remains in the retained
catalog and no agricultural rules are inferred.

## Exact next integration sequence

1. Inspect 7H's published SHA and its resolved PR #12–#18 contracts. Compare the
   table above and reserve the new package paths. Do not cherry-pick source exports
   into shared entrypoints or silently change the PR base.
2. After reviewing this draft, cherry-pick the 7I commit(s) onto a **new** follow-up
   integration branch. Leave both active worktrees untouched. Run the isolated
   suite against 7H's actual installed catalog, sanitizer, assistant and Rust.
3. Build the actual integrated v03_demo executable; configure its fixed absolute
   path and expected SHA-256. Keep the old v02/web executable endpoints separate.
   Approve the daily-only `power-daily-merra2.v1` contract, exact per-variable
   headers (`MERRA2+POWER` for hourly-derived extrema, `MERRA2` precipitation), LST
   dates and full evidence sidecars. Do not teach old Flutter parsers a new dataset
   by silently renaming it to old monthly MERRA-2.
4. Keep the standalone service on loopback initially. The example app owns its
   lifespan, queue and default local principal. Do **not** mount it publicly or
   simply include its routes into a hosted router. First replace the local-only
   boundary with reviewed hosted identity/session verification and inject a
   trusted principal into every store/job/object call. Request bodies must never
   choose owner IDs. Implement PostgreSQL/PostGIS and tenant object acceptance
   when that deployment is justified. Do not reuse one workspace token globally.
5. Reconcile #16 workspace photos explicitly: validate workspace-to-farm ownership,
   decode/re-encode with the existing sanitizer, copy authorized objects into the
   new private file store transactionally, and retain a migration audit. No old
   photo ID/EXIF/device location establishes a farm. Keep legacy storage available
   until migration verification succeeds; this PR does not delete legacy data.
6. #14 may consume `/farms/{id}/assistant-context` after its Pydantic contract test.
   Values are latest source daily facts, not Rust seasonal calculations. Preserve
   source URLs/IDs and `scope=regional`. Detailed Rust findings/context remain
   separate; do not invent translation for unsupported decision states.
7. Keep every #15 profile recommendation-ineligible. Regional pilot identity is an
   explicit caller-selected research scope, not automatic coordinate inference.
   Approve versioned crop IDs/system aliases, independent agronomic review and
   applicable numerical requirements before any new rule exporter. Farmer history
   is unreviewed and incomplete, so it must not silently authorize succession.
8. Obtain permitted ISRIC WCS/USDA/Australian/CMR/ASF/weather access; run opt-in live
   suites. Capture native metadata, license/release, access and QA receipts before
   promoting soil/raster diagnostic output. Never treat catalog candidates as
   valid acquisitions or local test rasters as live evidence. Review field support,
   cloud masks, shared radar pixels, run freshness and source applicability.
9. Run the full API/ownership/photo/migration/restore/job/real-Rust tests, then
   Flutter consumers and Android/Windows flows. Review OpenAPI/error handling,
   browser origin and hosted privacy boundaries. A production rollout remains a
   separate explicitly authorized action. Keep both PRs draft until accepted.

## API compatibility

New endpoints use `/api/platform/v1`. No existing `/api/v1`,
`/api/environmental/v1`, `/api/evidence/v1`, `/api/assistant/v1` or `/api/engine`
route is renamed or shadowed. New model fields must go through a version decision.
No `/radar` or forecast-success route is advertised: ingestion remains unfinished.
Providers report last attempted source status; liveness does not trigger probes.
Pending job deduplication includes owner and versioned geometry/period/product
keys. `succeeded` means processing completed and may contain explicit source gaps;
a failed source is never substituted with a fixture.
