# Soil photographs

Raw JPEG/PNG uploads reuse `earthsync.evidence.images.sanitize_image`:
10 MiB maximum before and after sanitization, format signature and actual decoder
validation, single frame, maximum dimension/pixel checks, decompression-bomb
handling, decode/re-encode into fresh PNG pixels, EXIF/GPS/XMP/text/profile removal.
Caller filenames and paths are ignored. No private image is served statically.

The local farmer app uses existing farm-owned object storage. Research test
images live in the separate private SQLite database as sanitized BLOBs, capped
at 500 photos and 256 MiB total image bytes. Downloads/deletions require their
own scopes and the exact farm grant. Private responses use `no-store`, `nosniff`
and sandboxed image content. Deleting an image cascades dependent lab reports.

Without a provider: `status: unavailable`, empty observations and measurements,
`chemical_measurements_available: false`. This is the actual tested default.

An operator may inject a documented `VisionProvider` through `create_app(vision=...)`.
It must name the actual image-capable model and declare image/external capability.
External adapters require consent on each analysis request before receiving pixels.
Returned fields are restricted to visible feature enums and visibility status;
no free-form diagnosis, pH, NPK, carbon, salinity, moisture percentages, confidence
scores, recommendations or arbitrary fields are accepted. Model observations
remain unverified and are never human-confirmed by the server automatically.

No external vision adapter, paid key, model capability evaluation or labeled
agricultural image-performance evaluation was available in this task. Mocked
provider tests exercise validation/consent only. Text-only Groq is not treated as
vision. The local farmer UI does not send photos to any external provider.

Ordinary soil images and home-test strips cannot supply chemical measurements.
Record human observations in the existing dated farm timeline; a confirmed
appearance remains a reported observation, not a laboratory test.
