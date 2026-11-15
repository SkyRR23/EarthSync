# Final real-time local release

Open PowerShell in the new final-version source folder and run:

```powershell
.\start-earthsync.ps1
```

The launcher selects free loopback ports, installs the locked Python environment,
builds native Rust and Flutter Web, checks actual readiness, starts the real-time
scheduler and secure research service, and opens the browser. The printed URL is
authoritative (normally http://127.0.0.1:8091).

```powershell
.\test-earthsync.ps1
.\test-earthsync.ps1 -Full
.\stop-earthsync.ps1
.\scripts\local\earthsync.ps1 logs
.\scripts\local\earthsync.ps1 status
```

Linux/macOS equivalents are `./start-earthsync.sh`, `./test-earthsync.sh` and
`./stop-earthsync.sh`. Python 3.12+, Rust/native build tools and Flutter 3.44 are
required. Set EARTHSYNC_FLUTTER to a Flutter executable to choose an SDK. Windows
automatically prefers an existing `~/develop/flutter-3.44.0` installation.

Private state is isolated in a marked sibling directory named
`<checkout-name>-demo-state`. Logs and process receipts stay in the ignored
`.earthsync-runtime` directory. The stop protocol signals only the current
instance and its own subprocess handles; it never kills arbitrary PIDs.
`scripts/local/earthsync.ps1 reset-demo -Yes` deliberately archives this marked
demo directory to a timestamped sibling; existing farmer stores are untouched.

The ordinary smoke test exercises actual HTTP, Rust readiness, crop RAG, a
temporary explicitly synthetic photo, report extraction, migrations, persistence,
NDVI availability and immutable scientific pins. It deletes only its temporary
test farm. The full option additionally runs offline backend/Rust/Flutter tests.
External-provider availability is reported separately from contract tests.

Earthdata is optional. Missing authorization gives cached real data with original
acquisition dates or an unavailable response. External vision is disabled unless
an operator has configured an approved provider; ordinary photos, crop retrieval,
manual observations and local OCR remain separate workflows. Tesseract is an
optional local executable; without it, reports support manual transcription.

## NDVI

NASA HLSL30_VI / HLSS30_VI v2 is read with the existing official earthaccess and
byte-budgeted HTTP range reader. A request is capped at 65,536 native cells and
512 cells per axis, with at most two active selections and 12 cached selections.
NDVI and Fmask must have identical projected metre grids at 30 m, accepted
encoding and matching native acquisition metadata. Values use the native int16
scale 0.0001. QA bits 0..5, high aerosol, fill and out-of-range cells are rejected.
Polygon clipping uses native cell centres. Coverage includes centres outside the
tile as missing. A nearest-neighbour PNG is explicitly reprojected to EPSG:3857
for Flutter's existing map implementation; rejected cells have zero alpha.
Inspection reads original native values, not colours. A result is one acquisition,
never a silent temporal composite. NDVI is not a suitability or yield claim.

## Migration reconciliation

Both published 040 SQL files remain byte-for-byte unchanged. The integer-keyed
registry accepts only either exact known 040 digest. Existing rows and their
digests are retained. New stores apply realtime 040, then additive 041; crop-only
stores retain crop 040 and add the real-time table through 041. Unknown checksums
still fail closed. Clean initialization and both upgrades/reopening are tested.

## Demo sequence

1. Dashboard: Ames public reference; distinguish stations, forecasts and alerts.
2. Satellite NDVI map: acquisition age, QA, coverage and a native pixel, or the
   honest unavailable state when Earthdata has not been configured.
3. Crops / Crop Intelligence: search maize or soybean and open cited evidence.
4. Farm Map: confirm a point and draw a field; source context remains distinct
   from farm measurements.
5. Photos / Image Analysis and Laboratory Reports: preview an upload, explain
   optional vision status, inspect/correct a real report transcription.
6. Rotation Comparison: baseline, Alternative A and Alternative B; finish with
   saved decisions and the farmer journal. All 60 crop rules remain blocked.
