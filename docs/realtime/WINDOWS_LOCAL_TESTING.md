# Windows launch and retest

Keep the user's existing checkout and private databases untouched. Use a fresh
folder and the exact reviewed SHA from this branch's draft PR.

Requirements: Git, Python 3.12, Rust 1.99.0, Flutter 3.44.0 / Dart 3.12.0, Visual
Studio C++ tools/Windows SDK. Use the original [release runbook](../release/RUNBOOK.md)
for destination ACL/security checks and complete staging packages.

```powershell
$Repo = 'C:\src\EarthSync-Realtime'
$Private = 'C:\earthsync-realtime-private'
git clone https://github.com/SkyRR23/EarthSync.git $Repo
git -C $Repo fetch origin feat/earthsync-realtime-final-v1
git -C $Repo checkout --detach <reviewed-commit-SHA>
Set-Location $Repo
py -3.12 -m venv C:\earthsync-realtime-tools
$Python = 'C:\earthsync-realtime-tools\Scripts\python.exe'
& $Python -m pip install -r server\requirements.lock
& $Python scripts\verify_7x_integrity.py
cargo build --locked --manifest-path engine\Cargo.toml --examples
cargo build --locked --release --manifest-path app\rust\Cargo.toml
Push-Location app
flutter pub get --enforce-lockfile
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run --dart-define=PLATFORM_URL=http://127.0.0.1:8021
Pop-Location
& $Python scripts\finalize_offline.py app\build\web
$env:PYTHONPATH = "$Repo\server"
$env:EARTHSYNC_EVIDENCE_DIR = "$Private\workspace"
$env:EARTHSYNC_EVIDENCE_TOKEN_FILE = "$Private\workspace\workspace-token.txt"
$env:EARTHSYNC_EVIDENCE_ORIGINS = 'http://127.0.0.1:8091'
& $Python -m earthsync.demo_workspace "$Private\workspace"
# PowerShell 7: masked entry, never put a literal token in shell history or chat.
$env:EARTHDATA_TOKEN = Read-Host 'Earthdata user token (optional for weather)' -MaskInput
& $Python scripts\run_final_local.py --directory "$Private\platform"
```

Open <http://127.0.0.1:8091/#/realtime>. Keep both services on loopback. The
worker is enabled by default; do not use multiple backend workers. If NASA is
not configured, weather remains usable and satellite cards show authentication
required. Earthdata login in a browser alone does not authenticate Python.

1. Select public Ames. Check Finch identity/distance and each sensor's actual UTC
   and Iowa-local time; verify soil depths rather than expecting every sensor.
2. Inspect next-24-hour/hourly and next-seven-day/daily NWS forecasts, precipitation
   intervals, issuer, valid times and current official alert-check state.
3. Leave the page open through a station update. Confirm the timestamp advances
   without restarting or pressing Refresh. Browser cache reads occur every 15 s;
   provider cadence and publication delay remain independent.
4. Inspect NASA's actual acquisition dates, model-vs-measurement labels, QA and
   regional resolution. October NDVI or multi-day SMAP must not look instantaneous.
5. Select Crawfordsville, Davis, Yangon and Mandalay. Myanmar must not display
   Iowa station data or NWS warning coverage.
6. Reopen/draw a field; open its monitoring link and compare baseline/A/B. Save
   and reopen a comparison; verify the deterministic assistant and protected photos.
7. Test English/Burmese and phone width. Stop/restart backend to verify cached
   stale/unverified states and persisted source/assessment records.
8. Stop both services; back up platform SQLite + objects and the separate workspace
   SQLite/token. Restore to **new** directories and verify before using the copies.

For live diagnostics, use new directories outside the checkout:

```powershell
& $Python scripts\realtime_smoke.py --directory "$Private\smoke-new" --all-locations
& $Python scripts\realtime_nasa_access.py --directory "$Private\nasa-probe-new" --authenticated
```

After stopping the app: `Remove-Item Env:EARTHDATA_TOKEN`. Never include tokens,
raw private databases, farm geometry or photo pixels in a support message. Report
the tested SHA, exact action, time, provider error code and a redacted screenshot
or log. A failed step is not user acceptance; interactive Windows testing remains
a separate user gate from Windows cloud CI.
