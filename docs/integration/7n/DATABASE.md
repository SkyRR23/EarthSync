# Farm identity, persistence and photo ownership

SQLite remains the local single-user evidence store. Migration 001 is unchanged;
new immutable migration 002 adds `farm_links`. Schema files are packaged with the
Python distribution. No PostgreSQL/PostGIS or hosted ownership protocol was added.

## Explicit identity and consent

| Identity | Meaning | Persistence |
|---|---|---|
| Flutter `ConfirmedFarm.id` | Local profile identity, never a database UUID by inference | Existing version-1 SharedPreferences profile |
| Full UTC `confirmedAt` | Revision of that explicit farm confirmation | Profile and server farm-link key |
| 7I `Farm.id` | Server-generated UUID under server-selected local owner | SQLite farm row |
| `(owner, local_profile_id, revision)` | Explicit mapping to one database UUID | Migration 002, unique composite key and owner/farm FK |

Opening a page only reads the mapping. Creating it requires choosing the declared
production system and clicking **Confirm local farm persistence**. It transfers
only the confirmed name, point, confirmation date and that system. It never copies
area/device location, photos, tokens or local notes. The server supplies ownership.

Creation and its audit event share `BEGIN IMMEDIATE`. Repeating the same explicit
link with the same content returns the same UUID, including after a lost 201
response or restart. Changed content under the same revision returns 409; a new
confirmation revision gets a new UUID. Old evidence/photos/decisions remain attached
to their original farm, preventing stale records from following a relocated farm.
No data are deleted when a confirmation changes. Old revisions are available in the
local database archive through their UUIDs; the active UI shows the exact active
link. No unverified pre-existing UUID is guessed from a nearby point/name.

The full confirmation time is the identity revision; `confirmed_on` remains the
7I date-only farm contract. Selected area and device position stay independent.
A missing/restored-away mapping asks for explicit persistence again, rather than
silently creating a duplicate. Local profile restoration must preserve the original
ID/time if it is intended to reconnect to an existing server farm.

## Evidence, history and decisions

Daily jobs accept the verified UUID only when the query point equals the confirmed
farm point. Evidence keeps its regional support; associating it with a farm never
turns it into a field measurement. Full versioned records remain immutable and
owner-scoped. The UI explicitly selects immutable snapshots; the server rejects
ambiguous/inapplicable evidence and preserves missing/rejected source states.

A real integration defect was fixed: source-cache canonicalization reordered JSON
metadata keys, making string comparison falsely reject unchanged evidence.
Immutability now compares parsed values and writes canonical JSON. Existing database
rows remain readable; an actual value change still returns 409. A repeated cached
regional/farm HTTP request is a regression test. No migration rewrites evidence.

Local crop-planning notes remain unchanged and farmer-reported. Saving historical
periods into the server is a separate explicit action. No automatic crop-name,
production-system, review or history-completeness inference occurs. No mutating
request is automatically retried. After an uncertain history/assessment submission,
refresh history before resubmitting; only the farm-link operation has a durable
idempotency policy. Valid Rust responses save their full input/output/lineage and
binary hash. Validation failures preserve the Rust error envelope and do not create
a valid decision. Every catalog profile remains reference-only.

## Photos and migration policy

7H workspace photos require their existing bearer capability and remain in the old
private store and gallery. 7I photos are separately farm-owned sanitized files.
A local profile ID or photo GPS does not prove permission to migrate either store.
The current release deliberately performs **no automatic photo migration**.

A future migration must verify the old workspace token on the source service,
require explicit per-photo selection and a currently confirmed destination farm,
retrieve only authorized sanitized pixels, re-run the sanitizer, and create the
new owned object transactionally with a source/destination/hash audit receipt.
Retries need a unique migration key. Failed object/database writes must roll back;
source objects must remain until a verified backup/restore and explicit retirement.
No tokens, EXIF, original filenames, private object paths or pixels enter chat.
This consented migration tool is not implemented or claimed as verified in 7N.

Existing farm-owned archive routes retain their local owner checks; no extra UI
was added simply to consume them. Unit/API tests exercise wrong farm/owner, image
integrity, sanitization, deletion and backup/restore. Hosted photo access remains
blocked by the lack of a reviewed multi-user identity/ownership architecture.

## Restart, backup and restore

Stop the single worker before complete backup/restore. Use the existing
`earthsync.platform_v1.maintenance` commands with **new absolute destinations**;
backup includes SQLite, referenced sanitized objects and a SHA-256 manifest.
Restore validates paths, object references, hashes, migration checksums and SQLite
integrity before returning. Failed restore removes only its new incomplete target.
Never overwrite the current data directory or put backups inside the web root.

In-flight jobs recover as retryable `WORKER_RESTARTED` failures; they are not silently
replayed. Completed/failed/cancelled statuses remain distinct. Cancellation is best
effort; already authorized saved evidence may remain. Transactions/quota rollback,
foreign keys, cross-owner isolation, changed-value rejection, repeat-cache recovery,
restart and restore are covered in platform tests and the 7N HTTP integration test.

## Final integrated recovery evidence

The final 7Q workflow is rehearsed against migrations 001 and 002. Exact installed
hashes are checked; injected failure uses the next version and rolls back all DDL.
The complete original platform store was backed up offline, restored to a new
private state root, and started under the final pinned Rust manifest. Farm UUIDs,
old decisions/evidence/job state and sanitized photo hashes survived. A fresh
uncached March POWER job then produced a new actual-Rust decision under the newly
validated executable hash. See `evidence/final-ops-database.json` and
`evidence/final-runtime-restore-live.json`. Original stores and backups remain.
