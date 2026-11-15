# Integrated 7Q operations status

7Q PR #23 at `ef9a67ced98c9af98d677a679c9ab1761dc8904a` is now merged into
this release candidate. `ops/staging/staging.py` is the canonical restricted
staging/artifact/backup workflow. It invokes the same existing web and platform
entrypoints; `scripts/run_final_local.py` remains a development convenience.
Do not run both supervisors against the same ports/data.

The SDK/Pillow/farm-ID/photo/job/security gates below are resolved or explicitly
bounded. Operations now defaults to Flutter 3.44, builds the Web platform client,
records the exact loopback browser/service origins, and hashes both included
Python lockfiles. A clean source checkout at the final full RC SHA is required.
Use the final verification report for tested commands/manifests and source SHA.

# Trusted local staging handoff for 7Q

This handoff is reviewable code/configuration, not permission for public deployment.
7N owns the final application branch and central integration. 7Q should keep its
scripts/backup work in its own worktree and independent PR; do not rewrite source
PRs #19/#20/#21 or auto-merge this draft. 7J's scientific audit remains independent.

## Runtime topology

```
Browser http://127.0.0.1:8091
  ├─ Flutter release assets + existing public/demo API contracts on 8091
  ├─ existing workspace-photo routes: private capability + loopback/HTTPS
  └─ separate http://127.0.0.1:8021/api/platform/v1
       loopback peer + Host + exact Origin; one server-selected local owner
       SQLite + private sanitized objects; actual hash-checked Rust v0.3 process
```

There is no private-platform mount or proxy through the web application. Never
publish port 8021, forward it from a public reverse proxy, trust forwarded peers,
allow wildcard origins, or treat this local principal as hosted authentication.
A public/multi-user release needs reviewed server-verified identity and ownership
on every farm/evidence/job/photo path; that work is not completed here.

## Reproduce the application

Use Python 3.12, Rust 1.99.0 for the backend/native tests, and Flutter **3.44.0** /
Dart **3.12.0**. The exact Flutter image digest and dependency-lock hash are in
source-manifest.json. Do not use Flutter 3.50 with the selected SDK localization
lock without resolving and revalidating it. Android's Cargokit channel resolves
its own stable Rust toolchain; record that exact version in the APK receipt.

From the final integration checkout, using a fresh private Python environment:

```sh
python -m pip install -r server/requirements.lock
python -m pip install --no-deps -e server
python -m pip check
cargo +1.99.0 build --locked --manifest-path engine/Cargo.toml --examples
cargo +1.99.0 build --release --locked --manifest-path app/rust/Cargo.toml
cd app
flutter pub get --enforce-lockfile
flutter build web --release --no-wasm-dry-run --no-web-resources-cdn --pwa-strategy=none --dart-define=PLATFORM_URL=http://127.0.0.1:8021
```

Use new, dedicated private paths **outside the checkout and web root**. Provision
the existing workspace capability without printing it, then run the new launcher:

```sh
# From repository root with that Python environment active:
PYTHONPATH=server python -m earthsync.demo_workspace /ABS/PRIVATE/workspace
export EARTHSYNC_EVIDENCE_TOKEN_FILE=/ABS/PRIVATE/workspace/workspace-token.txt
export EARTHSYNC_EVIDENCE_DIR=/ABS/PRIVATE/workspace/photos
python scripts/run_final_local.py --directory /ABS/PRIVATE/platform
```

On PowerShell set the two variables with `$env:EARTHSYNC_EVIDENCE_TOKEN_FILE=...`
and `$env:EARTHSYNC_EVIDENCE_DIR=...`; use the same Python launcher. The original
7H Run-WebDemo.ps1 remains available but does not implicitly start the new private
platform. Interactive Windows launcher/ACL/device execution is not newly claimed.

The launcher binds both processes to 127.0.0.1, disables forwarded-peer headers,
uses a single bounded platform worker, validates the dedicated directory and
pins the built executable/catalog hashes at startup. Closing it stops both
processes. Changing the web/platform ports requires matching the Web build's
PLATFORM_URL and exact permitted origin; rebuild rather than redirect private
calls through another origin. Liveness/readiness do not prove provider availability.

## Required staging checks

- `/api/v1/health` on 8091; `/api/platform/v1/ready` on 8021 must report storage and
  actual Rust startup probe success. `hosted_private_api_enabled` must remain false.
- A new farm is local until explicitly linked. Select the declared production
  system; confirm 201 and record only the returned nonsecret mapping receipt.
- Daily POWER is opt-in, separate from monthly climate; inspect queued/running and
  terminal state, original units/LST/lineage, source gaps and technical review scope.
- Select saved source snapshots and run a reference assessment; expect gaps and
  recommendation_eligible=false. Preserve all five engine states and validation.
- Restart, refresh the browser and verify the same link/history. Never copy private
  photos automatically. Browser tokens must be re-entered after refresh.
- Test rejection of wrong Host, unapproved Origin and non-loopback peer. Do not
  loosen checks to make a smoke test pass. No tokens/database files in build assets.

Reproduce the actual browser journey against **disposable test stores**, using a
session-private workspace token file:

```sh
python -m pip install playwright
python scripts/browser_7n.py --token-file /ABS/PRIVATE/workspace/workspace-token.txt
```

The script uses the installed `/usr/bin/chromium`, makes real API/provider requests
(or a documented cache of live responses), creates a labeled software-test farm,
and creates/deletes a generated nonprivate photo. Only its outage check simulates
transport failure. It never prints the capability or uploads photo bytes to chat.

## Complete backup/restore

Stop both service processes first. Keep the original 7H workspace (token, metadata
DB and sanitized objects) independently backed up with its existing policy. A
platform backup does **not** include the old workspace or browser SharedPreferences.
Export browser profile choices through the browser's trusted profile backup if
needed; preserve local farm ID + full confirmation timestamp to reconnect links.

```sh
PYTHONPATH=server python -m earthsync.platform_v1.maintenance backup --directory /ABS/PRIVATE/platform --backup /ABS/PRIVATE/new-backup
PYTHONPATH=server python -m earthsync.platform_v1.maintenance restore --directory /ABS/PRIVATE/new-restored-platform --backup /ABS/PRIVATE/new-backup
```

Destinations must be new, private and absolute. Restore rejects checksum/path/object
reference failures. Never overwrite the only current copy. Start the launcher with
the restored directory, check readiness, mapping UUIDs, evidence, history and photo
integrity before switching a staging shortcut. Keep the previous directory until
that acceptance completes. No cloud backup provider or publication is configured.

## Exact rollback

1. Stop the 7N launcher/processes; preserve its two private stores and browser profile.
2. Roll back a binary/release by switching its staging launcher to the retained,
   previously verified artifact. Never downgrade the platform database in place.
3. To reproduce the original source foundation without touching this worktree:
   `git worktree add --detach /NEW/ROLLBACK/CHECKOUT a7c33cc6b58703501bbba0ceba1bad1d6d42004b`.
   Use that revision's own documented Flutter 3.50/toolchain/lock and retained verified
   artifacts; 7N does not claim that toolchain is newly downloadable here.
4. The original 7H app uses its old private workspace; do not point it at platform
   SQLite. Leave 7I private data offline. No migration 001 was rewritten; migration
   002 is additive, but dropping it is neither required nor an authorized rollback.
5. For a 7N database rollback use the complete verified backup into a **new**
   directory, then explicitly switch the local launcher path. Browser mappings
   absent from that backup must be re-confirmed, never guessed by coordinates.
6. Keep this branch/PR draft. No main ref, source PR, public deployment, or data store
   is changed by these rollback instructions. A later code revert should be a new
   reviewed commit/PR, not a force-push of someone else's branch.

The reproducible API matrix, database mapping/photo policy, conflict report and
verification receipts are in this directory. Scientific/hosting limitations are
release gates, not permission to bypass source or privacy controls under the event
cutoff (15 November 2026, 18:00 Myanmar time).

## Final measured candidate and personal-server test

Application/operations artifact source:
`530c1e1d06c9202dfc1f5d06c659399409b7270f`. CI hardening/tests at
`ab745a027b7b66a6c63fb033b024b19053b12c55` do not alter those runtime sources.
All seven CI workflows and raw Windows/Linux logs pass. The complete browser
journey and new-directory restore/fresh uncached POWER → pinned Rust history pass.
See VERIFICATION.md and the hash receipts; Windows ACLs/device/server destination
checks remain explicit manual gates.

A dedicated trusted single-user personal server **can be tested** using the
canonical operations runbook and standard SSH local forwarding:

```sh
ssh -N -L 8080:127.0.0.1:8080 -L 8021:127.0.0.1:8021 user@personal-server
```

Open `http://127.0.0.1:8080` on the tester's computer. Keep both service listeners
on loopback and the browser origin exact. No private public proxy, wildcard CORS,
remote-peer override or invented authentication is supported. No server has been
accessed or deployed by 7N; approval is still required before any public deployment.

Latest 7J head `7b27699f13c94461a9d3d6596c47debfcfb9fed6` is now integrated.
The archive integrity/inventory blocker is resolved; new crop assertions remain
research-only and cannot feed the live catalog. The complete reproduction source
pin is `31cb7fd159ebb62c818bc6eee07274e0dde86e9b`. Runtime artifact hashes remain valid
because app/provider/engine/live-catalog and operations runtime code are unchanged.
