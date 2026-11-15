# Historical Agricultural Scenario Simulation Lab

Base: PR #29, `660b479c3ffb714cd1d489e1241c026ceae6ed67`. Isolated branch `feat/earthsync-historical-intelligence-v1`; integration target `feat/earthsync-final-product-completion`. Main, PR #29, PR #31, existing installations and private stores are not modified. No merge/deployment authorization.

The lab shares confirmed farm links/revisions, private SQLite, immutable Evidence,
provider transport, bounded Jobs, WaterPipeline, compiled Rust v0.3, reference
catalogs, journal chronology, saved decisions and rotation comparisons.

* `historical.py`: bounded archive manifests, summaries, seasonal mapping,
  pinned source projection and immutable simulation results.
* `historical_imagery.py`: capability-validated GIBS time selection; acquisition
  time stays unknown unless supplied by the provider.
* `historical_explanations.py`: saved descriptive summaries for the existing
  deterministic assistant. No new model or service.
* `032_historical_simulations.sql`: additive checksum-tracked migration. Two
  tables hold archive pointers and scenario results; no duplicate farmer journal.
* Flutter `/historical`: persistent Replay/Scenario/Results/Reported-history sections, farm selector, local replay, calendar controls, crop
  references, baseline/A/B assumptions, comparisons, lineage and device snapshots.

All new APIs are under `/api/platform/v1`:

| Method | Path | Behavior |
|---|---|---|
| POST | `/historical/jobs` | 1–366 historical LST days; confirmed farm revision required |
| GET | `/farms/{farm}/historical` | Bounded saved manifest list |
| GET | `/farms/{farm}/historical/{archive}` | Original evidence and replay series |
| GET | `/historical/imagery?day=YYYY-MM-DD` | Validates GIBS advertised time dimension |
| POST | `/simulations/jobs` | Three hypothetical strategies over at most eleven seasons |
| GET | `/farms/{farm}/simulations` | Lightweight bounded index |
| GET | `/farms/{farm}/simulations/{id}` | Exact immutable saved result |
| GET | `/farms/{farm}/decisions/{id}` | Exact owned strategy lookup for imports, independent of recent-list truncation |

Existing job status/cancellation endpoints apply. No writes retry automatically.
Pending identical jobs deduplicate. Complete source responses use the existing
cache; accepted archive pointers survive cache expiry and restart. Partial
archives preserve gaps and require explicit refresh to obtain a new version.
Replay never downloads an eleven-year archive on each slider movement.

Simulation inputs pin archive IDs, farm/revision, mode, decision timestamp,
periods, reference identities/scopes, hypothetical crop dates, assumptions,
priorities and optional parent/comparison. Date edits change period statistics
and Rust chronology. Water/resource edits change the recorded constraints and
unknown requirements; no unsupported hydrological model is implied.

A calculation digest excludes generated result IDs, decision IDs, parent/name
metadata and wall-clock creation time. Pinned source hashes and Rust executable
hash remain included. Duplicates with identical computational inputs reproduce
that digest. Editing uses a new ID; an existing ID with changed input is rejected.

Existing saved comparisons import as hypothetical sequences. Each season creates
new native assessments and a new saved comparison linked by the simulation; the
original comparison is retained. Current-reference traits are withheld from
as-of results. Historical reports recorded after the cutoff cannot feed Rust.

Single-process job admission, 120-second worker deadline, two workers, source
transport limits, SQLite quotas, loopback host/origin guards and private directory
permissions remain in force. GIBS capabilities alone have an 8 MB XML limit;
ordinary provider responses retain their existing 4 MB bound.
