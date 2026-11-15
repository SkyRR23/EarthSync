# Phone service failures: teammate deployment handoff

The Android release uses BACKEND_URL=https://fieldshift-yangon-2026.web.app.
Firebase Hosting's `/api/**` rewrite targets Cloud Run `fieldshift-backend` in
`asia-southeast1`. GitHub source merges and APK downloads do not deploy this
service. The teammate managing Google Cloud must inspect its revision and logs.

Required public app routes include:

- GET `/api/v1/environment/forecast?latitude=...&longitude=...`
- GET `/api/v1/environment/recent?latitude=...&longitude=...` (confirm the path
  against the mounted router in the deployed source)
- GET `/api/v1/environment/greenness?farm=...`
- POST `/api/v1/chat`
- POST `/api/v1/soil/estimate`

Deploy `server/Dockerfile` from the updated server source. It starts
`earthsync.api:app` on Cloud Run's assigned PORT. Confirm the Firebase rewrite
still names the intended service/region, the service accepts app requests, and
the revision includes the current routes. Configure GROQ_API_KEY on the server,
with access to its selected chat/vision models. Do not place keys in the APK.
Inspect Cloud Run logs for route failures, permission errors, upstream timeouts,
model/key rejection and missing NASA credentials. Do not log uploaded photos,
credentials or private farm payloads. Real provider outages remain unavailable;
no fixture data should be enabled to conceal them.

For the new note-advice implementation, open
`/api/v1/chat/capabilities`. The expected version is
`simulation-note-rag-v1`, with `reference_retrieval: true` and
`groq_key_configured: true`. This is deployment metadata, not proof that an
actual provider request succeeds. A previous connectivity fix does not establish
that this newer implementation was deployed. Package `chat_references.json`
alongside `chat_retrieval.py`; `server/pyproject.toml` includes the JSON in the
installed package.

The app now distinguishes HTML/invalid responses, missing routes, denied access,
server errors and transport failures. A generic phone error is not proof of a
Wi-Fi problem. This environment's outbound request to the Firebase hostname was
blocked by its network proxy, so no hosted-service health conclusion was drawn.

Android vegetation maps now use accepted HLS cells only. The coarse MODIS
fallback is excluded on Android. Gray/neutral outlines are field boundaries,
not plant-health measurements. All vegetation images retain source dates;
urban vegetation can have NDVI without being crops.

The latest primary offline simulation disables the satellite control explicitly:
no historical HLS pixels are bundled. The retained live endpoint searches the
last 75 days relative to the server clock, not the simulation date. Do not treat
that result as a historical simulation observation.

The HLS response now includes `availability` and bounded diagnostic counts:
`catalog_items`, `attempted_reads`, `unreadable_images`,
`cloudy_scenes_skipped`, and `insufficient_clear_pixels`.
`unreadable_images` means catalog images were found but all attempted reads
failed; it does not establish that imagery is absent. Check Earthdata access,
asset reads and provider responses in the deployed revision without logging
tokens or signed asset URLs. `no_catalog_items` and `no_clear_pixels` are
different outcomes. Cloud/quality checks are retained, not weakened to force
an image. These diagnostics require deploying the updated server source.

Native soil layers use ISRIC's public WMS display service directly, separately
from the app backend: pH, clay and sand, modeled top 0–5 cm at roughly 250 m.
Reference: https://maps.isric.org/soilgrids.html and
https://docs.isric.org/globaldata/soilgrids/wms_from_qgis_arcmap.html.
Display colours are not sampled field values or crop suitability. No present
soil moisture, live fertility, soil-health score or field accuracy is claimed.

Owner requested no automated or interactive tests. Compile the APK and let the
owner check its screens and provider availability on their phone.
