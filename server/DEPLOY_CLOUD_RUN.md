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

Then check `https://<service-url>/api/v1/health`.

**Phones use the Firebase Hosting address, not `*.run.app`.** On 14 Nov 2026
a Myanmar mobile network refused connections to `*.run.app` while
`*.web.app` worked, so `app/firebase.json` forwards `/api/**` from
`https://fieldshift-yangon-2026.web.app` to this service
(`firebase deploy --only hosting` from `app/`). The app's
`config/cloud.json` uses that address. Hosting-to-Cloud-Run requests time
out after 60 s.

Notes
- `--max-instances 2` caps cost and NASA POWER load; the service scales to
  zero when idle. The in-process cache is per instance (see README).
- Request logs contain the queried latitude/longitude. Agree a log retention
  and privacy policy before a public pilot (README "public deployment" notes).
- No credentials are needed: NASA POWER is open.
