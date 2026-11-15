# Research API boundaries

Credentials contain 256 random bits from Python `secrets.token_urlsafe(32)`.
Only SHA-256 digests are persisted; high entropy prevents practical offline
dictionary guessing. Keys have scopes, expiry, revocation and exact farm grants.
Tenant and subject must both match. Same-owner keys without the farm grant cannot
access its images/reports. Keys cannot be provisioned through the HTTP service.
Do not use the farmer workspace token in this API.

Authentication precedes body parsing. Raw streams are capped at 10 MiB for image
upload and 64 KiB elsewhere, including chunked requests. Four concurrent admitted
requests and a 45-second deadline bound processing; OCR has its own timeout.
The recommended server command additionally caps concurrent HTTP connections.
Per-key fixed-window rate limits persist in SQLite (60 requests/minute by default).
A process-wide 600-request/minute ceiling limits unauthenticated attempts.
The latter and admission are per process, so the documented MVP runs one worker.
This is not a distributed abuse-protection service.

Host and Origin allowlists are exact; no wildcard origins, browser credential
cookies or cross-site authenticated requests. HTTPS is required by default;
explicit loopback development uses `EARTHSYNC_RESEARCH_LOCAL=1`. The factory does
not trust forwarded headers. External deployments must review their TLS/proxy
configuration rather than forwarding arbitrary client-supplied scheme headers.

All private queries join an authorized farm grant. BLOB/image paths are generated
internally; caller paths/filenames/URLs are never used. Models forbid extra fields;
there is no arbitrary-source URL fetch, filesystem download, user document ingestion
into the RAG corpus, farm enumeration or approval endpoint. UUID parsing and
parameterized SQL apply to private resources. The sanitizer is inherited unchanged.

Audit rows retain key ID, fixed event, resource ID, time and status only; the latest
10,000 rows are retained. No token, OCR, note, location or body is logged. Uvicorn
access logs are disabled in the documented command. Production deployments must
also redact proxy logs and limit retention according to their own policy.

The research directory/database/backup and secret output file use owner-only
permissions on POSIX. Symlink/non-normalized paths and checkout state are rejected.
On Windows, prepare an owner-only directory with the repository's documented ACL
pattern before provisioning. NTFS ACL behavior is a destination acceptance gate,
not proven by POSIX `chmod`. Protect SQLite and backups with host disk encryption
and account ACLs; application-level image encryption is not implemented.

Backup: `python -m earthsync.research.cli --directory PRIVATE_DIR backup NEW_BACKUP`.
Stop workers before restore. Copy a protected backup into a new private directory
as `research.sqlite3`, run `PRAGMA integrity_check` and ownership tests, then rotate
or revoke restored credentials before exposure. A restored backup also restores
its old revocation state. Never overwrite a live database during testing.

The local farmer service retains its existing loopback/Origin/farm checks. Migration
040 adds laboratory records to its existing backup; original migration checksums,
Rust algorithms and existing source integrity remain unchanged. Deleting a photo
cascades its dependent report rows in both stores. Secure-delete is enabled, but
storage-media/backup erasure is an operational responsibility.
