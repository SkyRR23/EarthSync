# Windows local acceptance

Use Python 3.12+, Rust and the existing pinned Flutter 3.44.0 / Dart 3.12.0.
Install the repository's locked Python and Flutter dependencies. This branch
does not replace the release launchers or original Windows acceptance checklist.

In PowerShell from the checkout:

```powershell
$env:PYTHONPATH = "$PWD\server"
python -m pip install -r server\requirements.lock
cargo build --locked --manifest-path engine\Cargo.toml --example v03_demo --example web_engine
cargo build --locked --release --manifest-path app\rust\Cargo.toml
Set-Location app
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run --dart-define=PLATFORM_URL=http://127.0.0.1:8021
Set-Location ..
python scripts\run_final_local.py --directory C:\EarthSyncPrivate\crop-test
```

Choose a new private directory, with an owner-only NTFS ACL, outside the checkout
and any synced/public folder. Follow `docs/release/WINDOWS_ACCEPTANCE.md` and the
existing staging ACL wrapper. Never use an existing farmer database for synthetic
tests or overwrite it. Existing data require a complete stopped-service backup
before applying additive migration 040.

The research API can run separately on 8031 using the commands in TEAMMATE_API.md;
PowerShell environment equivalents:

```powershell
$env:EARTHSYNC_RESEARCH_DIR = 'C:\EarthSyncPrivate\research-test'
$env:EARTHSYNC_RESEARCH_LOCAL = '1'
```

Use a new secret file in that ACL-protected directory. Never put its contents in
chat, logs, browser assets or Git. Provision/revoke using `python -m
earthsync.research.cli`; run the Python client with `--credential-file`.

Tesseract is optional and must be installed from an operator-approved source and
available on PATH. Without it, extraction explicitly returns `ocr_unavailable`
and supports manual transcription/confirmation. No external OCR is substituted.
For the synthetic fixture generator pass `--font C:\Windows\Fonts\arial.ttf`.

Check Crops → select two reference crops → Crop intelligence → retrieve cited
claims. Check an unknown cultivar/region returns missing scope. On farm photos,
preview an ordinary image and see unavailable analysis without invented pH/NPK.
Upload the synthetic report, inspect its original image, correct one value and
confirm explicitly. Restart and reopen reports; rehearse backup/restore into a
new destination. Check both English/Burmese shell labels and narrow screens.

Interactive Windows/ACL/font/OCR acceptance must be performed on the teammate's
actual machine. Local Linux results are not represented as Windows acceptance.
The added CI includes Windows Python contracts; remote results must be inspected
at the actual branch head before making any CI claim.
