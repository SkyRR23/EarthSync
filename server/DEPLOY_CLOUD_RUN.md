# Deploy the climate backend to Cloud Run

Hosted so phones can reach it over HTTPS (the Flutter app's `BACKEND_URL`).
Project `fieldshift-yangon-2026`, region `asia-southeast1` (Singapore).
Needs a billing account linked to the project (Cloud Run + Cloud Build).

```sh
gcloud run deploy fieldshift-backend \
  --source server \
  --project fieldshift-yangon-2026 \
  --region asia-southeast1 \
  --allow-unauthenticated \
  --min-instances 0 --max-instances 2 --concurrency 20 \
  --cpu 1 --memory 512Mi --timeout 120
```

Then check `https://<service-url>/api/v1/health` and build the app with
`--dart-define=BACKEND_URL=https://<service-url>`.

Notes
- `--max-instances 2` caps cost and NASA POWER load; the service scales to
  zero when idle. The in-process cache is per instance (see README).
- Request logs contain the queried latitude/longitude. Agree a log retention
  and privacy policy before a public pilot (README "public deployment" notes).
- No credentials are needed: NASA POWER is open.
