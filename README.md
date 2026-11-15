# EarthSync — NASA Field Shift

EarthSync is a Flutter Web agricultural companion backed by Python FastAPI,
SQLite and the native Rust v0.3 evidence engine. A farmer confirms a field,
inspects dated environmental evidence, explores crop references, compares an
existing declared rotation with alternatives, and retains reports and decisions.

This is the **final local real-time integration**, starting from PR #35 and
combining the completed crop-intelligence PR #34 and multimodal RAG PR #36.
The foundation is the combined [PR #29](https://github.com/SkyRR23/EarthSync/pull/29) release. It includes
actual Iowa station observations, NWS forecasts/alerts, global model forecasts and
authorized, quality-controlled NASA point/cell evidence with honest acquisition
times and source delays, bounded QA-masked HLS-VI NDVI map overlays and private
photo/report workflows. Historical Simulation PR #33 is excluded.
There are **zero approved executable crop suitability rules**; all 60 candidates
remain blocked. Exploration never ranks a “best crop”, predicts income or gives
an irrigation prescription.

Run `.\start-earthsync.ps1` from this source folder in PowerShell, or
`./start-earthsync.sh` on Linux/macOS. The launcher builds missing components,
starts all local services, checks readiness and opens the printed browser URL.
Use `.\stop-earthsync.ps1` to stop and `.\test-earthsync.ps1` for actual HTTP smoke
tests. [Final startup, migration and demo guide](docs/release/FINAL_LOCAL.md).

- [Real-time implementation, coverage and measured evidence](docs/realtime/README.md)
- [Real-time verification and remaining gates](docs/realtime/VERIFICATION.md)
- [Real-time Windows launch and retest](docs/realtime/WINDOWS_LOCAL_TESTING.md)
- [Baseline implemented, partial and unavailable objectives](docs/release/COVERAGE.md)
- [Baseline combined verification](docs/release/VERIFICATION.md)
- [Baseline staging, private storage and rollback](docs/release/RUNBOOK.md)
- [NASA demonstration script and screenshots](docs/release/DEMO.md)
- [Source provenance, licenses and privacy](docs/release/PROVENANCE.md)
- [Full-stack Windows/Linux packages](docs/release/ARTIFACTS.md)
- [Verified hosting assessment and blockers](docs/release/HOSTING.md)
- [Required local Windows acceptance](docs/release/WINDOWS_ACCEPTANCE.md)

Use a fresh checkout of the reviewed PR head with Python 3.12, Rust 1.99.0 and
Flutter 3.44.0 / Dart 3.12.0. Keep private databases, tokens and photos outside
Git and static assets. Follow the runbook to build both pinned runtime profiles
and run them on loopback. No public deployment is claimed.
The final integration is gated on combined automated, scientific and runtime
checks. The current user request authorizes its merge once those checks pass;
older workstream-specific manual-acceptance notes remain historical context.

The application connects farm maps and modeled soil pH, sparse regional GFS
forecasts, NASA POWER historical climate and Rust FAO-56 reference ET0 to saved
rotation assessments. Three or more saved strategies retain their source scopes,
dates, unknowns and farmer priorities. Records distinguish actual reported
operations, plans, ground measurements supplied by a farmer, modeled products
and scientific references. Soil and forecast snapshots are reference context;
they do not become approved crop requirements.

The season view combines reported crop periods, explicitly declared bare/fallow
periods, unknown gaps, chronology conflicts, photos, environmental snapshots and
assessment history. New context offers explicit reassessment. Saved assessments
remain immutable and reassessment is on demand. The real-time backend separately
monitors environmental sources while running; browsers read its private cache.
A stopped local PC does not keep monitoring or delivering warnings.

Core interface labels support English and Burmese. Untranslated scientific
material remains English and requires local agricultural/language review.
Opt-in device caches support read-only saved records and crop references; original
retrieval times stay visible. Offline drafts require explicit submission after
reconnection. Private API responses, map tiles and rasters are excluded from the
public application-shell service worker.

New runtime receipts are kept privately; public release evidence contains sanitized summaries, hashes and location-free screenshots.

Historical development evidence is retained under `docs/integration/`; it is not
proof that a feature passed the final combined browser journey. Use the release
report for the baseline and `docs/realtime/VERIFICATION.md` for this candidate.
