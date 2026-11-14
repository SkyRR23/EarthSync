param([switch]$SkipBuild, [int]$Port = 8080, [string]$BindAddress = '127.0.0.1', [string]$EvidenceDirectory = '')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$python = Join-Path $PSScriptRoot 'server/.venv/Scripts/python.exe'
if (-not (Test-Path $python)) { throw 'Create server/.venv and install server/pyproject.toml dependencies first. See docs/WEB_DEMO.md.' }
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path $env:LOCALAPPDATA 'EarthSync/private-demo-evidence' }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
[IO.Directory]::CreateDirectory($EvidenceDirectory) | Out-Null
# Windows chmod does not establish a private ACL. Constrain this dedicated
# directory to the current Windows account and SYSTEM before retaining photos.
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
foreach ($account in @($identity, 'NT AUTHORITY\SYSTEM')) {
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($account, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $EvidenceDirectory -AclObject $acl
Push-Location server
try {
    & $python -m earthsync.demo_workspace $EvidenceDirectory
    if ($LASTEXITCODE) { throw 'Private workspace setup failed' }
} finally { Pop-Location }
$tokenPath = Join-Path $EvidenceDirectory 'workspace-token.txt'
$tokenAcl = New-Object System.Security.AccessControl.FileSecurity
$tokenAcl.SetAccessRuleProtection($true, $false)
foreach ($account in @($identity, 'NT AUTHORITY\SYSTEM')) {
    $tokenAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($account, 'FullControl', 'Allow')))
}
foreach ($file in (Get-ChildItem -LiteralPath $EvidenceDirectory -File -Force)) {
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Private workspace files must not be symlinks or reparse points.' }
    Set-Acl -LiteralPath $file.FullName -AclObject $tokenAcl
}
$env:EARTHSYNC_EVIDENCE_DIR = $EvidenceDirectory
$env:EARTHSYNC_EVIDENCE_TOKEN_FILE = $tokenPath
$env:EARTHSYNC_EVIDENCE_TOKEN = $null
if (-not $SkipBuild) {
    $env:CARGO_BUILD_JOBS = '1'
    cargo build --locked --manifest-path engine/Cargo.toml --example web_engine
    if ($LASTEXITCODE) { throw 'Rust engine build failed' }
    Push-Location app
    try {
        flutter pub get --enforce-lockfile
        if ($LASTEXITCODE) { throw 'Flutter dependency installation failed' }
        flutter build web --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run
        if ($LASTEXITCODE) { throw 'Flutter web build failed' }
    } finally { Pop-Location }
}
Write-Host "EarthSync binds to ${BindAddress}:$Port; local demo: http://127.0.0.1:$Port"
if ($BindAddress -eq '0.0.0.0') { Write-Host "Wi-Fi clients: open http://<this-PC-Wi-Fi-IPv4>:$Port on the same network. See server/docs/WINDOWS_RUNBOOK.md." }
Write-Host "Captured NASA replay: http://127.0.0.1:$Port/?climate=captured"
Write-Host "Real Rust API workbench: http://127.0.0.1:$Port/docs"
Write-Host "Private photos: enter the token from $tokenPath in Field photos. Do not share it."
Write-Host 'Photo access requires localhost or HTTPS. Climate and public context can be tested over local Wi-Fi.'
Push-Location server
try { & $python -m uvicorn earthsync.web_demo:app --host $BindAddress --port $Port --no-access-log }
finally { Pop-Location }
