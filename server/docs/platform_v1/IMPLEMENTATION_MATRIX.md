# 7I implementation boundary and audit

Audit 2026-11-14. Base e0cdaaf875efb376e3081a66826b4b5e21601c67.
Fetched all heads and PR refs before implementation. No published 7H integration
head or PR was present. PRs #10 and #12–#18 inspected as code, not just descriptions.

| Phase | Existing contract / gap | 7I boundary |
|---|---|---|
| 1 audit | #10 live historical POWER, compiled web Rust; #12 bounded errors/deadlines | This matrix and ownership handoff; shared services unchanged |
| 2 evidence | #17 environmental, #16 evidence.v1, #14 assistant.v1-proposal are distinct | New platform evidence v1 sidecar; no silent schema replacement |
| 3 climate | MERRA2 monthly working; #12 GEOSIT extension unapproved; v03 needs daily Tmin/Tmax | Independent daily MERRA2 contract, real captures, lineage/unit/calendar gates; GEOSIT remains rejected |
| 4 soil | #17 tested REST parser, deliberately reference-only, REST paused | Reuse via optional reviewed integration; investigate native WCS separately; no duplicated soil parser or invented values |
| 5 optical | #16 HLS unavailable, no numeric ingestion | Fixed-provider discovery, isolated bounded local-raster QA/extraction; no arbitrary URL downloads |
| 6 radar | #16 OPERA unavailable, no calibrated pixels | Compatible geometry/unit/processing metadata gates and local pixel summaries; access states retain blockers |
| 7 weather | #17 probe has no run identity, freshness unknown | Reusable source-health/forecast freshness; reuse #17, do not promote forecast without run identity |
| 8 storage | #16 private workspace photos only | Transactional owned farms/evidence/history/jobs/cache/audit and external object references; migrations and restore checks |
| 9 security | #16 one token = workspace, not farm/tenant; no hosted identity | Default-disabled local-only private API, owner-bound SQL, request/compute limits, no URL fetch input; hosted auth pending |
| 10 orchestration | #18 authoritative v03, #15 reference profiles have no exporter | Server-built request from owned stored evidence + catalog identities; actual pinned engine executable, no Python suitability |
| 11 pilots | #15 references, no field ground truth | Pilot source receipts and reproducible real/missing/conflict/software-only separation |
| 12 API | Shared api.py/routes owned by 7H | Standalone /api/platform/v1 with OpenAPI; no duplicate existing environmental/photo/chat routes |
| 13 jobs/cache | POWER in-memory cache; no persisted jobs | Bounded durable job records + worker, cancellation, deduplication, expiry and lineage-aware keys |
| 14 operations | Local runbooks, no combined production image | Isolated image/config, migration/backup/restore, local-only bind; hosted release blockers explicit |
| 15 validation | PR suites independently pass; no combined v03 path | Focused contracts/security/storage/provider/Rust/QA/job tests; opt-in network suite |

## Concrete audit findings

- Do not edit central api.py, web_demo.py, POWER v1, dependency locks, launcher,
  Flutter routing, engine types or FRB. They are active 7H integration surfaces.
- v03 requires explicit daily calendar, source IDs, quality and separate regional
  spatial support. A point-query regional raster is not field observation.
- Crop catalog production systems differ from v03 enums. Source desk review is
  not independent agronomic approval; all current profiles stay ineligible.
  Advisory calendars and soil temperature cannot become air-temperature rules.
- #16 stores bounded photos as SQLite blobs; acceptable for small demo but not
  large rasters. It does not implement cross-user ownership. Never expose it as
  a multi-user service or infer farm location from its metadata.
- #17 correctly refuses to promote weather without issue/run metadata. Its
  numeric readers are not independently live validated; preserve that state.
- Scientific gaps: no reviewed regional requirements, daily ET0 method inputs,
  field applicability, QA-checked live satellite pixels, validated radar
  interpretation, irrigation adequacy or ground-truth labels. No Python
  algorithm may fill these gaps.
- Bounded transport, queue admission, response size, database quotas, cache
  eviction and subprocess cleanup are required to avoid memory/task growth.
- Production release requires reviewed OIDC/session integration and operational
  spatial/database acceptance; this milestone must not advertise hosted privacy.
