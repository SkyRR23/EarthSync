# 7L verification evidence

Story: open EarthSync → explore a global area → retrieve real historical context →
optionally confirm a farm → inspect field/map/photo evidence → inspect reference
crop assessment → ask the deterministic assistant → inspect source limitations.

## Automated results

| Check | Outcome |
| --- | --- |
| Edited/new Dart files | 39 files formatted, 0 remaining changes |
| `flutter analyze` | No issues found |
| `flutter test --reporter expanded` | 102 passed; 3 opt-in live tests skipped; no failures |
| Final responsive and daily adapter checks | 11 passed, including the unconfigured daily route |
| `pytest server/tests -q` on pinned 7H code | 265 passed; 2 opt-in skips; one existing dependency deprecation warning |
| Actual native FRB library build | Passed, release profile, Rust 1.99 / FRB 2.13 |
| Live NASA → Python → native FRB/Rust → Flutter | 5 tests passed, including the opt-in live assertion |
| Live web HTTP → Python → Rust → rendered twelve-month result | 5 tests passed, including the opt-in live assertion |
| Actual 7I daily climate job | 1 passed: three NASA modeled records × 29 daily readings, source policy retained |
| Flutter Web release build | Passed with bundled renderer, no remote font/CDN prerequisite |
| Android debug APK | Passed for armv7, arm64 and x86_64 native bridge builds; not a device/emulator runtime test |

Offline fixtures are explicitly test inputs. No live failure is replaced by a
captured fixture. The live 7I job used the reviewed standalone factory, loopback,
real NASA transport, pinned Rust binary and pinned catalog; no backend code was
modified to make the consumer pass. The request was regional, with no fabricated
farm UUID or ownership claim.

## Requirement coverage

| Requirement | Evidence |
| --- | --- |
| First entry, GPS allowed/denied/unavailable, manual global area, skip | `global_onboarding_test.dart` |
| Explicit farm confirmation/edit, area/farm separation, restore | `global_onboarding_test.dart`, `home_profile_test.dart`, `system_integration_test.dart` |
| Climate charts, source dates/units, incomplete records, retry, same-query stale data | `dashboard_climate_test.dart`, `nasa_power_client_test.dart`, real browser chart capture |
| Actual Rust bridge and versioned result states | `native_bridge_test.dart`, `system_integration_test.dart`, `engine_envelope_test.dart` |
| Field/environment/satellite unavailable UI | `ui/responsive_product_test.dart`, retained backend evidence suites |
| Photo selection, error/cancel, consent revoke, explicit association, replacement and confirmed deletion | `photo_evidence/photo_evidence_test.dart` |
| Crop forms, valid dates, local per-farm storage, timeline, no recommendation promotion | `question_flow_test.dart`, `analysis_session_test.dart`, `ui/planning_preferences_test.dart` |
| Reference-only status, missing requirements, validation response | `system_integration_test.dart`, `web_engine_test.dart` |
| Assistant citations, stale contexts and unavailable service | `assistant/assistant_test.dart`, `system_integration_test.dart`, browser answer capture |
| 320/390/768/1024/1440 px layouts, desktop sidebar, secondary routes | `ui/responsive_product_test.dart` |
| Large text, dark theme and navigation semantics | `ui/responsive_product_test.dart` (320 px, 2× text) |
| Appearance/language persistence and Burmese font fallback | `ui/planning_preferences_test.dart`, `ui/responsive_product_test.dart` |
| Reviewed daily job HTTP 202, source failures, missing values, loopback boundary | `ui/platform_climate_test.dart`, opt-in `ui/platform_live_test.dart` |

## Browser evidence

Shared Chromium loaded the real release build from the existing demo host on
port 8091. Manual checks exercised welcome → labeled Nairobi area → real climate
charts → deterministic answer with citations → optional farm confirmation.
Screenshots are browser captures, not mockups or reference-image composites.
Coordinates shown are clearly labeled example-region/test-farm coordinates.

- [Welcome](screenshots/7l/welcome-desktop.png)
- [Regional dashboard](screenshots/7l/dashboard-desktop.png)
- [Live climate graphs and provenance](screenshots/7l/climate-desktop.png)
- [Deterministic assistant answer and citations](screenshots/7l/assistant-desktop.png)

DOM automation was unavailable in this environment; native Chromium input and
screenshots were used. DevTools was blocked by browser policy and was not bypassed.
During simultaneous Android/Web/test compilation the host ran low on memory and
Chromium displayed an “Aw, Snap” page. Leftover task-owned build daemons were
stopped and the page reloaded successfully; this is not counted as a successful
uninterrupted browser run. Responsive widget tests cover all stated widths.

## Build and integration boundaries

- APK is debug-signed and contains the real native bridge. No connected Android
  device/emulator was available for runtime verification. Release signing,
  distribution and production accounts are not claimed.
- The default UI uses 7H services. The 7I daily destination is opt-in and
  loopback-only; it is not an automatic farm/photo migration or hosted API.
- Live HLS/SAR ingestion and quantitative NDVI remain unavailable where the backend
  reports them unavailable. No yield/health scores or crop approvals were added.
- Burmese is a navigation preview requiring native/domain review; remaining
  workflows and scientific evidence stay in English. Spanish assistant catalogs
  are retained but no complete Spanish application is claimed.
- Farm crop notes persist separately and are not silently injected into Rust's
  reviewed crop/history evidence contract.
- Re-fetch confirmed 7H `5addde7` and 7I `b578a6d` unchanged at final comparison.
  Shared Flutter/router/theme/copy files still need ordinary reconciliation in a
  new final integration branch; no automatic merge has occurred.

## Raw receipts

Saved terminal output (with trailing terminal padding removed) is in [`verification/7l/`](verification/7l/), including the
full Flutter suite, final analyzer, backend suite, explicit live native/web/daily
checks, focused UI/photo/planning checks, final web build and final Android build.
The final photo check also opens the full-screen `InteractiveViewer` and closes it
before exercising replacement and the cancel/confirm deletion paths. The final
planning check runs after the typography correction.
