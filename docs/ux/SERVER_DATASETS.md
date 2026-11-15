# Server dataset registry

`GET /api/platform/v1/datasets` returns the versioned `earthsync.dataset-registry.v1` contract through the existing loopback/private FastAPI platform. Migration `042_dataset_registry.sql` extends its existing SQLite store. It does not replace user databases or existing providers.

A descriptor records dataset ID/name/publisher, HTTPS source, license, coverage, version, acquisition/update times, server-relative storage path, processing/validation status, units, resolution, access method, checksum, permitted device caching and redistribution restrictions. Public responses omit storage paths. Versions are immutable; re-registering identical metadata is idempotent. Import validates the path stays inside the designated dataset root, rejects symlinks and checks file bytes against the SHA-256.

Bootstrap records for ECOCROP, GAEZ, SoilGrids, NASA POWER and HLS are explicitly registration-only, not installed and not reviewed. All report `operational: false`; registering a file does not install a processing adapter or scientifically clear crop rules. Existing integrated NASA/SoilGrids/NDVI providers remain independent and retain their own actual availability.

## Register already acquired data

```powershell
$env:PYTHONPATH = 'D:\Nasa_spaceApp\earthsync-farmer-experience-v2\server'
.\.venv\Scripts\python.exe -m earthsync.platform_v1.datasets --state-dir ABSOLUTE_PRIVATE_STATE --dataset-root ABSOLUTE_DATASET_ROOT --register descriptor.json
```

The CLI registers a bounded JSON descriptor for an already acquired file. It does not download global datasets. Administrators can acquire/import new versions independently of Flutter releases; using a new scientific format still requires a compatible reviewed server adapter. `EARTHSYNC_DATASET_ROOT` selects the server root. Do not point the development server at another checkout's private state or dataset directory.

Cache and redistribution flags are metadata, not permission to bypass provider terms. Review the source license/access method before installing or returning a dataset. Larger rasters and crop archives remain on the server. `test_mobile_dataset_boundary.py` guards against bundling scientific files or server/data directories into mobile assets.
