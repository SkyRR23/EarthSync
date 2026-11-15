# 7X verification receipts

This candidate is delivered as draft PR #28. The final exact head, workflow URLs
and readiness recommendation are in the PR description after its final CI audit.
Do not infer readiness from a previous green head. `evidence/ci-code-green.json`
records the earlier all-green integration-code head
`5327a4af2df91d37922ed3226e5fa9f71ae1af45`; delivery adds acceptance/recovery
scripts, reports and receipts. Final-head checks remain authoritative.

## Local measured checks

| Gate | Actual result | Retained evidence |
|---|---|---|
| Combined 7N backend/scientific/assistant/photo/platform + 7Q operations, actual native consumers, live NASA enabled | **413 passed, 2 skipped** | `evidence/python-final-with-live-nasa.log`; only optional live soil/HLS probes skipped |
| Full offline backend run | **412 passed, 3 skipped** | `evidence/python-regression.log`; NASA subsequently explicitly enabled, not silently counted |
| Native Rust engine | **123 passed**, no failures/ignored | `evidence/rust-tests.log`; actual compiled examples built with locked Cargo |
| v1 crop catalog | **39 passed** | `evidence/7n-v1-catalog.log` |
| 7P offline / scientific / real native export | **55 / 14 / 5 passed** | `evidence/7p-offline.log`, `7p-scientific.log`, `7p-native.log` |
| 7P reproducibility / graph | **16 artifacts reproduced**, 708 crops / 75 profiles / 937 claims / 40 sources / eight rotations; zero executable requirements | `evidence/7p-build-check.log`, `7p-graph-check.json` |
| 7P explicitly enabled live sources/discovery | **4 passed** | `evidence/7p-live.log`; source/discovery checks, not accepted numerical soil/satellite evidence |
| Full 7V package/method/native checks | **32 passed**, zero skips | `evidence/7v-tests.log`, `7v-package.log`; all 60 candidates blocked |
| 7W numerical/provider regression | **11 passed** | `evidence/7w-water-tests.log`; synthetic numerical/fault fixtures and cached original NASA captures are distinguished below |
| Immutable hashes / derivative reconciliation | v1 exact hash; **49 v2 + 11 7V** artifact hashes; **35** original upstream input pins; **60** exact derivative matches; zero executable rules | `evidence/integrity.json`, `autocrlf-checkout.json`; fresh checkout with `core.autocrlf=true` and full 7V package check |
| Flutter native/offline suite | **113 passed, 3 explicit live skips** | `evidence/flutter-tests.log`; actual newly compiled native FRB library |
| Flutter opt-in live NASA/Web/platform | **11 passed**, no skips | `evidence/flutter-live.log`; both native and Web HTTP paths |
| Flutter analyzer / release Web | No issues; build succeeded with Flutter **3.44.0 / Dart 3.12.0** | `evidence/flutter-analyze.log`, `flutter-web-build.log`, `flutter-pub.log`; lock enforced |
| Actual Chromium 7W + 7X comparison / inherited 7N | **10 / 12 stages passed**, zero page errors | `evidence/browser-7w/results.json`, `browser-7n/results.json`; real release assets and FastAPI/Rust/SQLite |
| Docker construction / runtime smoke | Passed; no published port; read-only root and bounded private tmpfs | `evidence/docker-build.log`, `docker-smoke.log`; v2 lookup/blocked review/actual Rust/persisted decision, build/test sources excluded |
| Immutable 7Q Linux builds / both-process startup | Passed at the pinned integration-code head; rebuilt Web assets match the browser-tested assets byte for byte | `evidence/7q-linux-build.log`, `7q-linux-startup.log`, `7q-manifests.json`, `artifact-hashes.json`; Windows independently exercised in CI |
| SQLite restart / two-store backup / new-directory restore | **Passed**: exact rows in 11 platform tables plus workspace BLOB table; 14 decisions / 18 evidence records; both independent test photos verified | `evidence/recovery.json`, `recovery-baseline.json`, `recovery-photo-fixtures.json`; original and restored API verification and row/object hashes |
| Ruff/format/pip/rustfmt/diff | Passed | `evidence/static-checks.log` |

## CI and Windows scope

All **11 workflows** passed at the integration-code head above, including both
Ubuntu/Windows Python 3.12/3.13 matrices, actual Docker build/smoke, native/science,
catalog/blocked-candidate tests, Flutter bridge/analyzer/tests/Web, assistant/photos
and the additional **Windows 7Q build/startup** job. The final exact-head runs are
linked in the PR; inspect conclusions **and raw test logs** before accepting them.
The Bash matrix steps fail closed; no later command masks pytest's exit code.

The Windows job builds both profiles through `staging.ps1` with private ACLs,
resolves `flutter.bat`, initializes its tool before parsing strict machine JSON,
and starts both loopback services. Its startup probe checks actual Rust readiness,
v2 integrity/lookup, the blocked sidecar and built Web assets. It explicitly makes
no live NASA or Windows Chromium claim. Interactive 7W/7X Windows browser acceptance,
destination-specific firewall/ACL checks and Android runtime were not performed.
The user's prior 7N Windows visual test remains inherited evidence only.

## NASA provenance, numerical fixtures and outages

- `evidence/browser-7w/live-water-job.json` preserves the real job's `cache_hit`,
  original response hashes, retrieval timestamps, source products, definitions,
  units, dates/LST, geometry and eight saved records (seven provider inputs plus
  Rust-derived ET0). Reusing a cached original is never labeled a fresh request.
- The initial retained `diagnostics/initial-phone-scroll/live-water-job.json`
  records the uncached real five-day retrieval in this 7X environment. That
  browser attempt failed a later phone scrolling assertion; its successful API
  request is valid source provenance, **not** a full browser acceptance pass.
- Five-day `(42.0308, -93.6319)`, July 3–7 2024: saved Rust ET0 is
  **23.193683430451973 mm** and rainfall **28.68 mm**, five usable days each.
  Flutter displays those exact persisted numbers. The assistant claims and
  citations use the same saved values. These describe regional historical inputs.
- The inherited seven-day original capture has 59.97 mm rain, six usable ET0
  days and **null complete-period ET0** because July 2 is outside the accepted
  radiation method domain. Original source bytes and FAO-56 intermediates remain
  retained under 7W; no missing day is fabricated or silently dropped.
- FAO-56 Example 18 is a labeled numerical software fixture: native ET0 about
  3.8796934649677484 versus published rounded 3.88 mm/day, with explicit tolerance
  and intermediate checks. The 7V 358.50/381.00 mm interpolation example is
  synthetic arithmetic. Neither is an actual field/crop water observation.
- Browser farms, proposed sequence dates, history and generated recovery photos
  are labeled software-test inputs. Chronological support/conflict does not make
  a Myanmar reference applicable at the Iowa example point or promote any rule.
- Browser outage tests deliberately abort transport. The provider-outage regression
  raises transport errors and checks seven gaps and null water quantities. These
  are explicit fault injections, not a claim of a real NASA outage. There is no
  fake response, zero-valued fallback, new weather or calculated irrigation.
- SoilGrids nodata remains rejected; numerical GAEZ, HLS/Sentinel pixels and
  forecast/alert acceptance are unavailable. The two optional live soil/HLS probes
  remain skipped. Discovery metadata and reachable references are not numerical
  provider integration.

## Browser evidence and diagnostics

The canonical 7W runner includes all eight inherited stages plus two 7X checks:
two saved alternatives with actual Rust chronology support/conflict, and both
retained on refresh. The unchanged 7N journey's twelve stages exercise explicit
farm confirmation/link, live or original-cache daily NASA evidence, source
selection, actual Rust, saved attributed history, assistant citations, protected
photo upload/deletion, navigation/phone rendering and outage recovery.

Usable screenshots are retained in `evidence/browser-7w/` and `browser-7n/`:
`real-water-calculation-desktop.png`, `water-phone.png`,
`alternative-sequences-desktop.png`, `assistant-persisted-reference-and-water.png`,
and the inherited navigation/photo/persistence screenshots. The JSON API receipts
are adjacent. No token, private production photo or EXIF is included.

`evidence/diagnostics/` retains superseded partial runs. The runners originally
scanned before Flutter's scroll/semantic tree settled and one 7N selection did not
retain all three checked snapshots. The corrected runners wait for the route,
settle scrolls, check selection state and assert the exact selected-source count.
Assertions and actual API requirements were retained. A comparison screenshot
also needed its real controls brought into view because an ancestor semantic label
can include off-screen descendants. Superseded captures are not canonical release
acceptance and do not contribute passed-stage totals.

## Remaining limits

No calibrated suitability percentage, soil measurement, preferred crop, yield,
profit, nitrogen/pest credit, accepted crop curve or field irrigation prescription
is delivered. All 60 7V candidates remain blocked, Kc development/late interpolation
requirements are preserved, and ETc/water-balance outputs remain null without
accepted evidence. See [product coverage/roadmap](PRODUCT_AUDIT.md) for the point
versus polygon gap, local-only notes, partial comparison workflow and future work.
