# Full-stack local release artifacts

The Flutter live-integration workflow builds and smoke-tests one Windows package
and one Linux package, then uploads them as `earthsync-<system>-full-stack-<SHA>`
on the final PR. Each contains a zip, its SHA-256 sidecar and a runtime smoke
receipt. Artifacts expire after 14 days; reproduce them from a clean reviewed
checkout rather than relying on permanent GitHub artifact storage.

The zip includes this commit's tracked runtime sources, scientific catalogs,
migrations, bundled rights notices, public Web build and both host-native Rust
executables. It contains no `.git`, private archive history, databases, tokens,
runtime photos, virtualenv or device/browser state. Existing labeled source/test
fixtures remain fixtures, never live observations. Python 3.12 and its locked
dependencies are still required. Rust/Flutter SDKs are not needed merely to run
the prebuilt artifact. Native system/architecture must match the artifact.

## Identity and integrity

Download from the successful final-head workflow; compare the artifact digest
and `*.zip.sha256` against its CI receipt. Standard PR workflows build GitHub's
temporary **merge candidate SHA**, which may differ from the PR head SHA. Verify
the workflow's head SHA, its checkout/merge SHA and `release.json.source_sha`;
do not silently substitute a moving branch. The original completed source graph
is recorded in [provenance](PROVENANCE.md).

After extracting to a new dedicated folder, verify every file before executing
the package. Checksums detect corruption; the trusted reviewed CI source/digest
establishes artifact identity. Keep environments and private data outside it.

```powershell
$Package = 'C:\earthsync-release' # new extraction destination
$ExpectedSha = 'REPLACE_WITH_EXACT_REVIEWED_CI_CHECKOUT_SHA'
$env:PYTHONDONTWRITEBYTECODE = '1'
py -3.12 -B "$Package\source\scripts\package_release.py" verify --directory $Package --expected-sha $ExpectedSha
if ($LASTEXITCODE -ne 0) { throw 'Release verification failed' }
```

## Windows local startup

Use a new PowerShell terminal, a private NTFS destination outside OneDrive/public
directories, and a separate dedicated tool directory. The following creates
owner/SYSTEM-only ACLs on a **fresh** private directory. It does not change ACLs on
an existing directory or migrate any previous farmer data.

```powershell
$Package = 'C:\earthsync-release'
$Private = 'C:\earthsync-demo-private'
$Python = 'C:\earthsync-demo-tools\Scripts\python.exe'
if (Test-Path -LiteralPath $Private) { throw 'Use a fresh dedicated private directory' }
[IO.Directory]::CreateDirectory($Private) | Out-Null
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
foreach ($account in @($identity, 'NT AUTHORITY\SYSTEM')) {
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($account, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
  $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $Private -AclObject $acl
py -3.12 -m venv C:\earthsync-demo-tools
& $Python -m pip install -r "$Package\source\server\requirements.lock"
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed' }
& $Python -m pip check
if ($LASTEXITCODE -ne 0) { throw 'Dependency verification failed' }
Get-ChildItem Env:EARTHSYNC_* | Remove-Item
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:PYTHONPATH = "$Package\source\server"
$env:EARTHSYNC_EVIDENCE_DIR = "$Private\workspace"
$env:EARTHSYNC_EVIDENCE_TOKEN_FILE = "$Private\workspace\workspace-token.txt"
$env:EARTHSYNC_EVIDENCE_ORIGINS = 'http://127.0.0.1:8091'
& $Python -m earthsync.demo_workspace "$Private\workspace"
if ($LASTEXITCODE -ne 0) { throw 'Workspace setup failed' }
& $Python -B "$Package\source\scripts\run_final_local.py" --directory "$Private\platform"
```

Open **http://127.0.0.1:8091**. The private backend remains **127.0.0.1:8021**.
Stop with Ctrl+C. Restart the final command with the same private directory and
source artifact. Close older app tabs before accepting a new offline shell.
No current local ports may already be occupied. Do not publish these ports or
put the package/private directory behind a public file server.

For an immutable source-build/manifest workflow with startup hash checks on
every run, use the existing [7Q Windows runbook](RUNBOOK.md#windows-powershell).
The unpacked snapshot has no Git repository and is not a `staging.py` source-pin
checkout; use a fresh Git checkout for that alternative. Never edit manifests to
make a different source/binary acceptable.

## Linux package reproduction and smoke

From a clean pinned Git checkout with built public Web assets and native examples:

```bash
python3.12 -B scripts/package_release.py build --sha "$(git rev-parse HEAD)" --output /absolute/artifacts/earthsync-linux.zip --v03 "$PWD/engine/target/debug/examples/v03_demo" --web-engine "$PWD/engine/target/debug/examples/web_engine"
python3.12 -m zipfile -e /absolute/artifacts/earthsync-linux.zip /absolute/artifacts/unpacked
python3.12 -B scripts/package_release.py verify --directory /absolute/artifacts/unpacked --expected-sha "$(git rev-parse HEAD)"
# Dependencies must already be installed from server/requirements.lock.
# This creates fresh disposable private state, starts both loopback services,
# runs native missing-data and HTTP/access checks, and stops the services.
python3.12 -B scripts/ci_package_startup.py --package /absolute/artifacts/unpacked --expected-sha "$(git rev-parse HEAD)" --private /absolute/private/package-smoke
```

Python's zip extraction may not retain Unix executable modes; the smoke helper
sets owner-execute on the two verified native artifacts. When launching manually,
set those modes after checksum verification. Keep OS/tool versions and native
shared-library compatibility aligned; a Linux zip is not a Windows or ARM zip.

For backup/restore use the existing [recovery instructions](RUNBOOK.md#backup-restore-and-rollback)
with both services stopped, separate workspace/farm stores and a new private
restore destination. Preserve the previous package and its matching pre-upgrade
backup; never roll back by deleting migration tables.

The zip is **not a hosted deployment**, a standalone Python distribution, or
proof of interactive Windows acceptance. [Hosting](HOSTING.md) and
[local Windows acceptance](WINDOWS_ACCEPTANCE.md) retain their explicit gates.
