param([switch]$SkipBuild, [int]$Port = 8080)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$python = Join-Path $PSScriptRoot 'server/.venv/Scripts/python.exe'
if (-not (Test-Path $python)) { throw 'Create server/.venv and install server/pyproject.toml dependencies first. See docs/WEB_DEMO.md.' }
if (-not $SkipBuild) {
    $env:CARGO_BUILD_JOBS = '1'
    cargo build --locked --manifest-path engine/Cargo.toml --example web_engine
    if ($LASTEXITCODE) { throw 'Rust engine build failed' }
    Push-Location app
    try {
        flutter build web --no-wasm-dry-run
        if ($LASTEXITCODE) { throw 'Flutter web build failed' }
    } finally { Pop-Location }
}
Write-Host "EarthSync live demo: http://127.0.0.1:$Port"
Write-Host "Captured NASA replay: http://127.0.0.1:$Port/?climate=captured"
Write-Host "Real Rust API workbench: http://127.0.0.1:$Port/docs"
Push-Location server
try { & $python -m uvicorn earthsync.web_demo:app --host 127.0.0.1 --port $Port }
finally { Pop-Location }
