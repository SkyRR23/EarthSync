# 7N final integration verification

Draft PR: https://github.com/SkyRR23/EarthSync/pull/24. No main merge or public
deployment. The application and operations artifact source pin is
`530c1e1d06c9202dfc1f5d06c659399409b7270f`; subsequent test/CI/report changes do
not alter its application, engine, provider, database or operations runtime code.
The final PR head is reported separately when delivery completes.

## Integrated source identities

| Source | Exact integrated head |
|---|---|
| 7H #20 | `a7c33cc6b58703501bbba0ceba1bad1d6d42004b` |
| 7I #19 | `b578a6df2764479ff9c9df006cc00e5ddb3ccfa3` |
| 7L #21 | `bd8d245b0eae92aab353d852baf05adba5527384` |
| 7J #22, including the later precision correction | `d7e43399c9fd296032e64b1c1b5623dbeb70cca6` |
| 7Q #23 | `ef9a67ced98c9af98d677a679c9ab1761dc8904a` |

All five remote heads were rechecked and remained unchanged. The original PRs and
other worktrees were not rewritten. The separate tested 7I precision patch is
applied, with its artifact hash in source-manifest.json; its adjacent-point tests
are retained and out-of-domain response coordinates are also rejected.

## Measured tests and builds

| Check | Result / evidence |
|---|---|
| Combined local backend/operations regression | 400 passed, 3 explicit provider skips before the final recovery-report test; that complete operations suite subsequently passed 20 tests. `evidence/backend-and-ops-tests.log`, `evidence/ops-tests.log` |
| Scientific contract and operations focus | 40 passed, including J01–J06 boundary checks. `evidence/science-ops-tests.log` |
| Rust engine, including 7J field-history regressions | 118 passed. `evidence/engine-tests.log` |
| Actual native FRB bridge | 6 passed. `evidence/bridge-tests.log` |
| Crop catalog + immutable archive inventory tool | 45 passed (39 catalog + 6 inventory), 32 subtests. `evidence/catalog-inventory-tests.log` |
| Complete Flutter suite against rebuilt native Rust | 109 passed, 3 explicit opt-in live skips. `evidence/flutter-tests.log` |
| Flutter analyzer and formatter | No analyzer issues; 108 Dart files checked, 0 changes. `evidence/flutter-analyze.log`, `evidence/dart-format-final.log` |
| Python/Rust static checks | Ruff lint/format, pip compatibility, rustfmt and all-target Clippy passed; CI repeats the relevant checks. `evidence/engine-clippy.log`, `evidence/bridge-clippy.log` |
| Release Web build from clean pinned source through integrated 7Q | Passed, enforced dependency lock and bundled renderer; platform client enabled. `evidence/final-ops-web-build.log` |
| Android debug APK after scientific Rust rebuild | Passed; arm64-v8a, armeabi-v7a and x86_64 bridge libraries verified. No emulator/device or release-signing claim. `evidence/android-build.log`, `evidence/android-artifact.json` |
| Actual Chromium acceptance on final pinned Web/runtime artifacts | All 12 stages passed, 0 unhandled browser errors. `evidence/browser-rc/results.json` |
| Complete migration/corruption/backup recovery rehearsal | PASS across all current migrations; bad checksum/object/reference and injected DDL rollback verified. `evidence/final-ops-database.json` |
| Process restart, retained state, new-directory restore and fresh pinned execution | PASS. `evidence/ops-restart-final.json`, `evidence/final-runtime-restore-live.json` |

CI results are recorded separately below; no skipped, blocked or cached-provider
check is relabeled as an uncached live success.

## CI acceptance

All **7 workflows / 16 checks** passed at CI hardening commit
`ab745a027b7b66a6c63fb033b024b19053b12c55`. Raw logs were inspected after
metadata review: Linux platform jobs report **401 passed, 3 skipped**; Windows
platform jobs report **398 passed, 6 skipped**. Three skips are opt-in provider
checks on both platforms; Windows additionally skips three POSIX-only fault
executables while still executing the actual compiled Rust. The Windows recovery
report test verifies the truthful INCOMPLETE manual-ACL gate rather than suppressing
it or skipping the recovery exercise.

| Workflow | Recorded successful run |
|---|---|
| Python backend, Ubuntu/Windows × Python 3.12/3.13 | https://github.com/SkyRR23/EarthSync/actions/runs/43603151392 |
| Evidence platform, same matrix + actual container build/smoke | https://github.com/SkyRR23/EarthSync/actions/runs/43603151440 |
| Flutter full integration/bridge/Web | https://github.com/SkyRR23/EarthSync/actions/runs/43603151434 |
| Rust engine | https://github.com/SkyRR23/EarthSync/actions/runs/43603151414 |
| Scientific regressions | https://github.com/SkyRR23/EarthSync/actions/runs/43603151418 |
| Assistant backend/UI | https://github.com/SkyRR23/EarthSync/actions/runs/43603151405 |
| Photo contracts/UI | https://github.com/SkyRR23/EarthSync/actions/runs/43603151396 |

`evidence/ci-verified.json` records conclusions, source SHA and raw-log counts.
`evidence/ci-before-fail-closed-fix.json` deliberately marks the earlier green
metadata as **not** passing raw-log audit. It must not be used as release evidence.
The delivery commit adds receipts/runbook/reproduction support only; its final
checks are inspected before the final response.

## Exact environment and artifact identities

Managed Linux, Python **3.12.14**, Flutter **3.44.0**, Dart **3.12.0**, backend/host
Rust **1.99.0**, FRB **2.13.0**, Chromium **156.0.8078.79**. Android used JDK
**21.0.9**, Gradle **9.4.1**, NDK **28.2.13676358**, and Cargokit's resolved stable
Rust **1.100.0**. The Android source application tree is identical to the final
artifact pin; this equivalence and all three binary hashes are recorded.

The available Flutter distribution matches the exact 7L image digest. The 7L
lock was inspected and enforced without a blind overwrite; all Flutter CI uses
3.44.0. Combined Python dependencies retain **Pillow 12.2.0** and Windows tzdata.
Both included lockfiles are hashed by operations builds. See CONFLICTS.md for
why 3.50 was not selected. No dependency upgrade was needed for 7J.

`evidence/final-artifacts.json` records full executable/FRB/lock SHA-256 values.
The final platform executable is
`533c65583bedb998a98e62eb690311ad3aa8c5eae6e797001015755b18ed870b`.
Startup checks this recorded manifest hash and executes the binary. Fresh HTTP
assessment output matched that exact hash; no integrity check was weakened after
the 7J Rust changes. Private build manifests/stores remain outside the repository.

## Real browser and live-provider scope

The final Chromium runner uses the actual release assets, two real Uvicorn
processes managed by 7Q, actual compiled Rust and SQLite. It verifies:

1. Useful onboarding without GPS and explicit farm confirmation restored on refresh.
2. Explicit HTTP 201 local-farm/revision → database UUID mapping.
3. High-precision farm-point daily POWER jobs: 202 submission and bounded status
   polling, full source/unit/quality disclosure, three 29-day February records.
4. Explicit immutable source selection → actual Rust → saved reference findings.
5. 201 historical report and decisions surviving browser refresh.
6. Deterministic assistant receiving persisted evidence/decision context with exact
   source IDs, without tokens, photo bytes or EXIF.
7. Workspace authorization, generated **labeled synthetic** test-image upload,
   confirmed 204 deletion and token loss after refresh.
8. Functioning primary/supporting destinations, desktop sidebar and phone layouts.
9. Explicit simulated transport outage followed by a real monthly API recovery.

The runner's 12 measured stages and screenshots are in `evidence/browser-rc/`.
Its February request may use the restored cache of previously fetched live bytes;
the receipt preserves `cache_hit` and retrieval dates. This is runtime/browser
acceptance, not a claim that every browser request fetched fresh NASA bytes.

Separate opt-in live Flutter verification passed **all 11 checks**, with no skips:
NASA → Python → actual native FRB/Rust → Flutter, Web HTTP → compiled Rust →
twelve-month rendering, and the daily platform client. See
`evidence/final-live-flutter-tests.log`.

The 7Q HTTP exercise independently verified **uncached** February POWER and
queued → running → succeeded transitions. Its initial report is intentionally
INCOMPLETE pending a real restart; the paired restart report passes after service
generation changed. On the final restored runtime, a **new uncached March query**
verified three 31-day records with original response hashes, exact farm association,
actual hash-pinned Rust and a newly persisted decision. See
`evidence/ops-live-smoke-final.json`, `evidence/ops-restart-final.json`, and
`evidence/final-runtime-restore-live.json`. No fixture substituted for provider data.

Live SoilGrids/HLS/OPERA/forecast acceptance was not newly established. Previous
source reports' proxy/access failures remain limitations, not live successes.

## Defects found and resolved during integration

- True 7H/7L dashboard conflict: retained complete UI and newer validation branch;
  compile checks caught and fixed the initially missing provider import.
- Persisted farm identity: explicit transactional, idempotent mapping prevents
  duplicate creation after lost 201 responses and stale evidence after farm edits.
- Daily cache: canonical JSON key order incorrectly triggered immutable-evidence
  conflicts. Parsed value comparison fixes retries/cache reuse while still rejecting
  a changed source value. The original live failure and corrected check are retained
  as diagnostic evidence, not silently counted as success.
- Backend CI exporter: Git paths were relative to `server/`; commands now anchor
  to the repository root and are tested from that working directory.
- Scientific defects J01–J06: complete reviewed fixes, including precision follow-up,
  exact response hashes, calendar/duplicate guards and confirmed-field history.
- 7Q migration rehearsal: original version-001 count and version-002 fault injection
  collided with the new mapping migration. It now checks exact installed migration
  hashes and injects the next version; rollback testing remains intact.
- CI raw-log audit found a masked Windows test failure despite green metadata.
  Native PowerShell commands allowed later checks to overwrite pytest's exit code.
  Both Python matrices now use fail-closed Bash execution. The recovery-report test
  explicitly preserves Windows' INCOMPLETE ACL gate while testing all portable
  recovery checks. Historical green metadata is retained with an invalid-audit flag.

## Security, staging and remaining issues

**Restricted Linux single-user demo P0:** no unresolved implementation or verification
blocker remains within this scope. Application integration, source integrity,
scientific fixes, persistence, Web/Android builds, browser/restore flows and the
fail-closed CI matrices are verified, including the raw Windows logs.

**Personal server:** **yes**, on a dedicated trusted single-user host using the
integrated 7Q runbook and standard SSH local forwarding for **both 8080 and 8021**.
Both backend listeners stay on 127.0.0.1, forwarded-peer headers stay disabled and
the platform admits only the recorded loopback browser origin. No personal server
has been accessed; no external deployment has occurred. Public/multi-user private
access is blocked without reviewed server identity and per-resource ownership.

**P1:** interactive Windows ACL/process checks; Android device/emulator execution
and release signing; destination-specific personal-server acceptance; consented
workspace-to-farm photo migration tooling; complete typed OpenAPI success schemas
and the existing duplicate operation-ID documentation warning. Old photo storage
and its working authorized gallery remain available. Burmese navigation remains
explicitly unreviewed and is not complete localization.

**P2 / withheld capabilities:** accepted quantitative soil/satellite/forecast data,
full hosted multi-user identity/authorization and scientific model extensions.
7J's new split archive is still blocked on part 03; no unverified Myanmar profiles,
archive calculations or generated artifacts were imported. All crop profiles remain
reference-only, recommendation-ineligible and without invented agricultural rankings,
suitability percentages, nitrogen/pest credits or yield/profit forecasts.

Public exposure of private APIs is a release blocker for any public deployment,
not a gate to bypass for this restricted demonstration. Exact source/conflict,
API, database/photo and rollback details are in CONFLICTS.md, API_MATRIX.md,
DATABASE.md and HANDOFF_7Q.md; canonical staging commands are in
`ops/staging/README.md`. The two complete private stores and original backup were
retained during restore; no source data were overwritten.
