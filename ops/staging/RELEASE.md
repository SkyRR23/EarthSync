> Final 7N integration: use `docs/integration/7n/VERIFICATION.md` for measured
> acceptance and `ops/staging/README.md` for the combined source pin and commands.
> Original 7Q milestone gates below are historical handoff context; no deployment
> approval is implied. Personal-server testing remains restricted to a trusted
> single-user host and SSH loopback forwarding, with private APIs unpublished.

# 7Q release and rollback gates

No server deployment is authorized by this document. The final source pin and
the destination-specific environment are pending. Do not promote 7H/7I/7L or
this operations branch as an integrated 7N release candidate.

## Tonight's restricted rehearsal

- [ ] Select the reviewed source(s), source SHA(s), SDK versions and dedicated private state roots.
- [ ] Verify manifests, correct v0.3 CLI, dependency locks and available disk space.
- [ ] Start one loopback worker per existing service; inspect health and actual readiness.
- [ ] Run the disposable database recovery suite and uncached historical NASA smoke.
- [ ] Stop/restart; verify persisted farm, evidence, terminal job, decision and photo.
- [ ] Verify the complete final Flutter journey, private photo authorization and actual assistant response.
- [ ] Verify outage/recovery, denied permissions, invalid requests and clear missing-data states.
- [ ] Rehearse full offline backup/restore; preserve both previous data and build artifacts.
- [ ] Verify on the actual personal server and actual Android/device if used; record the host/operator/time and exact results privately.
- [ ] Freeze the accepted restricted demo. If a required component is blocked, keep the block visible and use only the accepted narrower demo scope.

## After 7N supplies a final reviewed candidate

1. Record its full 40-character SHA, PR/check URLs, reviewed migration set, selected Flutter SDK and resolved Python lock. Fetch exact objects, create an independent detached build worktree, and verify `git rev-parse HEAD` plus a clean application tree.
2. Build on the target OS/architecture with pinned Python/Rust/Flutter versions. Use the existing native entrypoints, Cargo.lock, pubspec.lock and approved lock. Record tool outputs, all build commands, binary/web/catalog hashes and migration hashes. Verify the actual Rust protocol, not only a compiler or package version. A new candidate needs a new state root/manifest; do not reuse an old venv silently.
3. Check migration compatibility **on a protected copy** of a complete current backup. Compare schema_migrations checksums against the candidate SQL. Run candidate migration and integrity/object checks on that copy. Test the previous release against its pre-migration backup. Stop if a migration changed in place, an object is missing or an incompatible schema requires a reviewed migration plan.
4. Build a transfer set containing exact source (`git archive FULL_SHA`), code-only web/Rust artifacts for the target ABI, lockfiles, migration files, operations tooling version and checksums. Exclude `.env`, state directories, databases, photos, tokens, local browser profiles, provider credentials, SSH material and logs. Review the file list before transfer. Do not copy virtual environments across OS/path/ABI boundaries. Prefer a fresh pinned rebuild on the target and compare the retained artifacts appropriately.
5. Record the source archive and artifact SHA-256 values independently (Linux `sha256sum`, Windows `Get-FileHash -Algorithm SHA256`). Verify again after transfer. Transfer commands require the agreed server details and explicit authorization; none are executed by these scripts.
6. Provision the target private data/environment separately using restrictive filesystem ownership/ACLs. Confirm that loopback services are unreachable from the network. Do not install a public proxy for 7I. If users require separate private accounts/farms, stop at the identity/authorization blocker and retain the safe single-operator configuration.
7. With the writer stopped, create and validate a full backup. Stage the new release alongside the prior one. Start locally, require service readiness plus actual Rust execution, then run the accepted disposable HTTP/browser/device smoke and an authorized read-only check of retained user records. Do not inject software-test farms into actual user data.
8. Obtain the user's explicit approval for the concrete destination/configuration/artifact SHA before external deployment. Keep the prior release and backup until acceptance. If authorized, record actual transfer/startup/migration/test results and timestamps; a prepared command is not a completed deployment.

## Rollback drill

Stop new workers first; preserve logs and the failed data directory. Restore the
pre-migration complete DB/object backup into a new directory with the previous
verified source/binary/lock. Confirm integrity and old migration checksums, then
switch the private data directory offline. Start one worker and verify known
farm/evidence/decision/photo plus readiness. Record any post-backup writes that
need reconciliation; do not claim zero data loss after restoring an older backup.
Do not delete volumes, overwrite the only backup, downgrade SQL by hand or replay
queued work automatically. Pending/running 7I jobs become explicit retryable
`WORKER_RESTARTED` failures and require intentional resubmission.

## Exact status record to complete at acceptance

```text
Operator / local time with zone:
Personal or team host (keep infrastructure details private):
Authorization reference / permitted exposure:
7N full reviewed source SHA / PR:
Operations tooling SHA / PR:
OS / architecture / Python / Rust / Flutter:
Source archive / executable / web / catalog SHA-256:
Dependency lock / image digest if applicable:
Database migration versions / checksums:
Backup location + protected checksum / restore result:
Liveness / readiness / real Rust execution:
Uncached NASA date range / provenance verification:
HTTP exercise / restart / database / browser / device report paths:
Actual start / shutdown / transfer / deployment actions:
Unavailable providers and restricted functionality:
Previous release + data backup / tested rollback result:
Decision: ACCEPT RESTRICTED DEMO / BLOCK / AUTHORIZED DEPLOYMENT
```
