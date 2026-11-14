# EarthSync — NASA Field Shift

EarthSync is a Flutter Web agricultural companion backed by Python FastAPI,
SQLite and the native Rust v0.3 evidence engine. A farmer confirms a field,
inspects dated environmental evidence, explores crop references, compares an
existing declared rotation with alternatives, and retains reports and decisions.

This is a **local release candidate**, published in [PR #29](https://github.com/SkyRR23/EarthSync/pull/29).
Main is not updated while mandatory release gates remain unmet. Numeric NDVI
observations and official warnings are unavailable in the tested provider scope.
There are **zero approved executable crop suitability rules**; all 60 candidates
remain blocked. Exploration never ranks a “best crop”, predicts income or gives
an irrigation prescription.

- [Implemented, partial and unavailable objectives](docs/release/COVERAGE.md)
- [Combined verification and exact evidence classifications](docs/release/VERIFICATION.md)
- [Local startup, Windows commands and rollback](docs/release/RUNBOOK.md)
- [NASA demonstration script and screenshots](docs/release/DEMO.md)
- [Source provenance, licenses and privacy](docs/release/PROVENANCE.md)

Use a fresh checkout of the reviewed PR head with Python 3.12, Rust 1.99.0 and
Flutter 3.44.0 / Dart 3.12.0. Keep private databases, tokens and photos outside
Git and static assets. Follow the runbook to build both pinned runtime profiles
and run them on loopback. No public deployment is claimed.

The application connects farm maps and modeled soil pH, sparse regional GFS
forecasts, NASA POWER historical climate and Rust FAO-56 reference ET0 to saved
rotation assessments. Three or more saved strategies retain their source scopes,
dates, unknowns and farmer priorities. Records distinguish actual reported
operations, plans, ground measurements supplied by a farmer, modeled products
and scientific references. Soil and forecast snapshots are reference context;
they do not become approved crop requirements.

The season view combines reported crop periods, explicitly declared bare/fallow
periods, unknown gaps, chronology conflicts, photos, environmental snapshots and
assessment history. New context offers explicit reassessment. Refresh is on
demand; there is no background monitoring or push-warning service.

Core interface labels support English and Burmese. Untranslated scientific
material remains English and requires local agricultural/language review.
Opt-in device caches support read-only saved records and crop references; original
retrieval times stay visible. Offline drafts require explicit submission after
reconnection. Private API responses, map tiles and rasters are excluded from the
public application-shell service worker.

New runtime receipts are kept privately; public release evidence contains sanitized summaries, hashes and location-free screenshots.

Historical development evidence is retained under `docs/integration/`; it is not
proof that a feature passed the final combined browser journey. Use the release
report for the current candidate and its remaining limits.
