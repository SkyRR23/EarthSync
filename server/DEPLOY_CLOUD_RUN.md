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

## Test host (separate from live)

For team testing, a second service `fieldshift-backend-test` runs the same
code with the same limits, and a Firebase Hosting preview channel `test`
forwards its `/api/**` to it. The live service and `web.app` address the
phones use are not touched.

```sh
# test backend (newest code on the branch)
gcloud run deploy fieldshift-backend-test --source server \
  --project fieldshift-yangon-2026 --region asia-southeast1 \
  --allow-unauthenticated --min-instances 0 --max-instances 2 \
  --concurrency 20 --cpu 1 --memory 512Mi --timeout 120 --labels env=test

# test address, expires after 7 days (run from app/; re-run to renew)
firebase --config firebase.test.json hosting:channel:deploy test \
  --expires 7d --project fieldshift-yangon-2026
```

The channel prints its address
(`https://fieldshift-yangon-2026--test-<id>.web.app`). Like live, it has no
key and no CORS: phones, scripts and servers can call it; web pages on other
addresses cannot. When the channel expires its address stops working; the
test service stays (scales to zero) until deleted with
`gcloud run services delete fieldshift-backend-test --region asia-southeast1`.
