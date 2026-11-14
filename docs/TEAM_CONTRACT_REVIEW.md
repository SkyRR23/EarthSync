# Review of proposed PR #2 against Milestones 1–3A

Inspected `docs/TEAM_CONTRACT_v1.md` directly from `docs/team-contract-v1` at
`b30cae1ef20c6ed35969046f2fa6bc59ab6008e8` on 14 November 2026. The document is
**PROPOSED**, not approved. No files from that branch were merged or replaced.
The user-confirmed Rust-on-device/Flutter Android architecture remains in force.

| Proposed PR #2 boundary | Current engine / conflict | Required agreement |
| --- | --- | --- |
| §§3–5: monthly series always exactly twelve January–December values; `/api/v1/environment?...&year=` returns `EnvironmentalContext` | Correct for legacy `analyze_field`, insufficient for dated multi-year `SeasonalRequest` and November–February windows | P2/P4 choose a separate/versioned dated response or explicit adapter across years; do not reinterpret old arrays or break old clients |
| §3 ISO dates, §4 free-text `period` | Seasonal API uses explicit `{year,month}` objects and inclusive full months, not parsed free-text periods | Agree boundary conversion, calendar, order, duplicate handling and unsupported partial months |
| §§4–6 simple mean of twelve monthly means | Legacy behavior retained; seasonal output is day-weighted only for declared complete monthly means of daily means | P2 confirms daily aggregation semantics and P4 labels each statistic distinctly |
| §§5–6 rainfall daily ingestion to monthly totals; incomplete months null | Direction is compatible, but dated records additionally need per-variable completeness flags, explicit units, source/dataset/kind; single source/period strings lose evidence | P2 documents actual product rate-to-total conversion, coverage, metadata, scale and retrieval dates; do not infer complete from finite values |
| §5 `/crops` and `/crops/{id}` with systems/nullable numeric bounds and crop-level source list | No accepted deserialization into `decision::CropProfile`; current foundation uses per-system profile IDs, per-fact source IDs/status and explicit unsupported requirements | P2/P4 approve adapters, system IDs, evidence scope and unknown mappings; do not treat proposed nullable thresholds as deployed rules |
| §4 exactly three legacy scenarios with string sequences and unvalidated statuses | Legacy unchanged; separate foundation accepts one explicit baseline plus at least two alternatives, typed steps, per-step dates/system IDs and three eligibility states | P4 decides versioned integration and per-step UI; preserve old result keys/status; unknown is never suitable |
| §§4,12 planned Rust modules/functions and no verified build | Historical snapshot: climate helpers, seasonal API and validated tests now exist; crop comparison is additive under `decision`, not those placeholder signatures | Update implementation inventory after team review; proposed signatures are not generated bindings |
| §8 shared fixtures in `docs/fixtures/` | Current validated fixtures reside in `engine/tests/fixtures/`; all are explicitly synthetic | Agree shared ownership/path and cross-language compatibility tests before copying or replacing fixtures |
| §9 PRs into main | User explicitly requires stacked feature PRs, current 3A target `feat/seasonal-climate-analysis` | Follow task-specific target; no merge authorized |

Unchanged alignment: Flutter Android-first via flutter_rust_bridge v2, mandatory
on-device Rust decisions, backend data/provenance ownership, network-free pure
calculations, separate GIBS maps, server-only secrets and visible mock/live labels.

The primary plan's Myanmar demo and 33-hour MVP take priority over the proposal's
open product-marketing question. This code does not decide broader market scope,
backend technology, final license, or presentation/submission policy.

This review records proposed resolutions only. P2/P4 have not approved schema v1,
new endpoint names or generated bridge bindings. No outbound team messages sent.
