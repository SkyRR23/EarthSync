# 7N handoff

Consume only reviewed commits from `fix/earthsync-science-audit-v1`. This branch
targets exact final 7H for an independent draft review. It does not merge 7H,
7I or 7L, and does not edit another worktree, FastAPI application entrypoint,
Flutter router, central database code or the 7N branch.

## Concrete patch boundaries

1. `server/earthsync/source_validation.py`, `server/earthsync/power.py`,
   `server/tests/test_science_audit.py`, and the small NASA mock correction in
   `server/tests/test_backend.py`: J01–J04. The mock now echoes requested
   coordinates; formerly its hard-coded Yangon point passed arbitrary global
   coordinate tests because production never checked geometry. No real capture
   was altered. Keep exact response SHA-256 in provenance/cache/exports. Include
   the follow-up coordinate-serialization repair: the initial `06145ee` guard
   alone was too strict for POWER's observed three-decimal response coordinates.
2. `engine/src/v03/assess.rs`, `engine/tests/science_audit.rs`: J05. Scope crop
   and fallow history to confirmed field for succession independently of the
   rule's `field_only` flag. No ABI/schema changes; preserve existing contracts.
3. `tools/science_audit/` and `docs/science-audit/`: independent research tooling,
   source inventory and results. The original archive is now fully inventoried after checksum verification; scientific acceptance remains separate.

Do not apply the 7H monthly provider changes to 7I's independent daily parser:
its geometry/calendar/duplicate/hash protections already exist. If 7N retains
the default 7H monthly history path, that path still needs these fixes.

**7I does need J06:** apply
`docs/science-audit/patches/7i-power-coordinate-precision.patch` after the 7I
provider files exist in the integration tree. It modifies only that provider and
adds `test_science_coordinate_precision.py`. `git apply --check` and `git apply`
were exercised on a separate exact 7I export; all 85 platform tests then passed
with the three explicitly opt-in live tests skipped. Unpatched 7I fails its new
high-precision query regression. Preserve strict rejection of an adjacent
three-decimal point; tolerance is serialization association, not field accuracy.

After the Rust patch, rebuild the web executable and native bridge artifacts from
reviewed source. If a deployment pins executable SHA-256, recompute and explicitly
update its reviewed deployment pin; do not weaken 7I's binary integrity check.
No dependency/lockfile upgrade is required.

## Demonstration acceptance

Run the Jan/Feb 2024 NASA regression and the current source-capture/real-engine
HTTP tests. Missing source geometry, a mismatched point, duplicate daily JSON
keys and an annual/invalid date key must fail closed. One missing rain date must
leave rainfall unknown while preserving valid temperature. NASA data remain
modeled regional context, distinct from the confirmed farm.

Run `cargo test --locked` including the new history regressions. No regional
crop/fallow record can prove the confirmed farm's predecessor or fallow. Existing
sequence order/overlap, missing ET0/Kc, unit, synthetic and unreviewed-rule tests
must continue to pass. Availability must not become irrigation sufficiency.

Keep the current catalog reference-only, all recommendation flags false, candidate
approvals false and executable rule lists empty. Preserve full source sidecars and
missingness when linking 7I to the final application. No weighted suitability
engine, market-count finance proxy or automatic nitrogen/pest credit is accepted.

## Completed archive handoff

Original archive reconstruction and full SHA-256 verification succeeded. All 600
files were inventoried; 487 generated build files were rejected and never run.
All 113 extracted source/data originals remain unchanged. Sixty environmental
files match PR #11; 12 Myanmar crop assertions, six raw POWER responses, source,
methods and tests were independently reviewed.

Do not integrate contributed contexts, raw CSVs, old engine or crop rules into
live workflows. The old engine passes its 13 provided tests but fails all 12 new
scientific acceptance probes. Its five-year comparison, baseline planting month,
rotation deduplication, unverified support, irrigation, N and income behavior are
reproduced in `ARCHIVE_FINDINGS.md` and `evidence/historical-regressions.txt`.

`data/research/science-audit-v1/myanmar-reference-only.json` is deliberately
outside the live catalog and uses a distinct research schema. All 12 profiles
are recommendation/candidate-ineligible, with zero executable rules. Preserve
these guards, original citations, cached/unavailable source states and missingness.
The independent research validators reject shifted/annual month labels, conflicting
months, unit/statistic drift and incomplete year-month coverage. Do not use
calendar-normal arithmetic as a farm measurement or crop water sufficiency claim.

Forecast acceptance remains a separate source-contract task. Generic v0.3 issue
**date** cannot represent verified run identity and subdaily freshness. Preserve
current adapter rejection/unavailability until an exact model/run interface and
scientific applicability are accepted. Stage Kc, independent reference ET0,
root-zone storage, effective rainfall and delivered irrigation are still required
for a real irrigation assessment. No main app or central integration change is
included in this audit.

Source-review limits are explicit: 11 directly readable ECOCROP sheets and one
cached-only sunflower reference; World Bank original report cover dated June 2019;
FAO handbook full-text access unavailable. No missing or unavailable source was
promoted, and no independently verified farming advice is claimed.
