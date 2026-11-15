# 7Q verification and exact deployment status

Verified on November 14, 2026 in the managed **Linux x86_64 workspace**, using
Python **3.12.14** and Rust **1.99.0**. This was not a connection to the personal
server or team server. No external deployment, reverse proxy, public listener,
cloud resource or team-server transfer was created.

## Executed successfully

| Check | Observed result |
| --- | --- |
| Independent worktree/branch | `ops/earthsync-staging-v1` from supplied 7H SHA; only `ops/staging/` changed |
| Native platform build | Existing 7I exact lock installed in fresh venv; Cargo `--locked --release` builds actual pinned #18 v03_demo; package compatibility and SHA verification pass |
| Real Uvicorn | Actual platform factory on **127.0.0.1:18021**, one worker, no proxy headers/access logs; SQLite + actual Rust startup readiness true |
| Live historical NASA | Uncached real POWER February 1–29, 2024 retrieval; 3 records with response hashes/lineage and correct sample-point association; queued → running → succeeded observed |
| Rust/history/photos | Actual compiled v0.3 returns reference-only insufficient information; decision stored; sanitized PNG stored separately and retrieved with hash/no-store |
| Existing 7H backend HTTP | Real assistant returns claims against the 3 persisted NASA sources; private photo list rejects no token and accepts the private token; unknown API stays 404. No frontend build implied |
| Service restart | Farm, 3 live evidence hashes, terminal job, decision and private image persist across actual stop/restart |
| Stronger restart assertion | A second rehearsal records supervisor generation; checking before restart fails as expected, checking after a new generation passes |
| Lifecycle | SIGINT and SIGTERM shut down the worker and release its lock; immediate restart works after the port probe fix for TIME_WAIT |
| Maintenance exclusion | Backup while the service runs fails closed; after shutdown, maintenance backup/restore succeeds to a new directory |
| Restored live-data DB | 1 sample farm, 3 real evidence records and 1 decision in the restored snapshot; integrity/FKs and referenced photo hash valid |
| Dedicated DB recovery suite | All 8 reported checks PASS: initial/repeat migration, integrity/FKs, complete object round trip, corruption/missing references, migration DDL rollback/checksum recovery, quotas, missing files and POSIX privacy |
| Fault injection | Actual API + production HTTP transport with injected 503 yields 3 retryable source gaps, zero evidence/cache records and no raw provider body or synthetic fallback |
| 7I regression suite | **83 passed**, no skips in selected non-live platform tests; exported #15/#16 interfaces and real Rust enabled |
| 7H backend suite | **268 passed, 2 explicit live checks skipped** after actual web_engine prerequisite build |
| 7H engine suite | **111 passed** using committed Cargo.lock |
| Operations safeguards | **11 passed**: origin restrictions, false-green prevention, sanitized failures, exclusive maintenance, symlink paths, clean source pins and overlapping state/source rejection |
| Static checks | Ruff lint/format, Bash syntax, Python compilation and `git diff --check` |

The first 7H backend run began before its prerequisite binary finished compiling
and failed missing-executable checks. The ordered rerun after the build passed.
This was a verification ordering issue; no application edits were made. Both
Python suites emit the existing Starlette/AnyIO deprecation warning. The two 7H
live skips are not counted as live verification; actual 7I live HTTP retrieval is
reported separately above.

The restart rehearsal exposed an operations bug: a plain preflight socket bind
could reject an immediate restart while connections were in TIME_WAIT. The probe
now follows POSIX address-reuse behavior while rejecting an existing listener;
Windows uses exclusive address binding. Linux restart/shutdown were exercised.
Windows behavior remains unverified.

## Evidence and interpretation

- [Database report](evidence/database.json): disposable temporary directories only.
- [Live exercise](evidence/live-http-exercise.json): correctly returns INCOMPLETE before restart acceptance.
- [Live restart](evidence/live-http-restart.json): actual retained live records, not fixture substitution; the operator stopped/restarted the service.
- [Expected premature restart failure](evidence/expected-premature-restart-failure.json): negative test, intentionally FAIL; prevents claiming persistence without a restart.
- [Build and lineage hashes](evidence/build-and-live-lineage.json): actual binary/catalog/lock/migration and three real NASA response hashes, with private runtime data omitted.
- [7H backend HTTP](evidence/web-backend-http.json): actual assistant and photo authorization, with Flutter acceptance explicitly blocked.

Raw receipts, DBs, sanitized test images, secrets and complete logs remain outside
source in dedicated private `/tmp/earthsync-7q-*` paths. These are ephemeral
workspace artifacts, not durable off-host backups. Real-server backups must use
private persistent storage and independently protected retention. Process restart
persistence does not imply `/tmp` retention across host replacement/reboot.

## Not executed or still blocked

**No personal-server access or test is claimed. No team-server access or deployment
is claimed.** The final 7N RC SHA and reviewed combined runtime are pending.
The original 7H/7I/7L pins are audit inputs, not a final release.

Flutter and PowerShell are absent here. Flutter SDK installation, web build/full
browser acceptance and interactive Windows ACL/startup/stop checks were not rerun.
Backend tests do not establish complete Flutter UI behavior. Upstream 7H/7L
build reports do not substitute for 7Q verification. The 3.44 versus 3.50 Flutter
documentation/CI discrepancy and differing Pillow locks are explicit handoff gates.

Docker is installed but has no prepared 7I image here. The existing Dockerfile,
Compose, digest pins, volume and entrypoint were reviewed; no Docker build/run,
Docker Desktop behavior or container-volume restore is claimed. Prefer the native
verified restricted path until that separate drill passes.

No physical Android device, USB reversal, Wi-Fi, remote HTTPS boundary or hosted
identity has been verified. Complete final UI → platform association belongs to
7N acceptance. Soil/HLS/radar/forecast availability and crop recommendations remain
constrained as documented upstream. Unavailable providers remain explicit gaps.

Private multi-user team access remains blocked by the lack of reviewed hosted
identity/authorization. Retain the single-operator loopback/tunnel/USB demo, with
private data and credentials separate from release artifacts.
