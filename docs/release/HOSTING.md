# Full-stack hosting assessment — November 15, 2026 (Myanmar)

No public deployment is claimed. The final combined PR remains the release
candidate; main requires local Windows acceptance and explicit user approval,
in addition to engineering/scientific gates. No account, plan, billing, DNS,
tunnel, Access policy or public endpoint was changed during this assessment.

## Connected Cloudflare account

The connected account identity and account inventory succeeded. Resource checks
returned these results; account identifiers and email are intentionally omitted:

| Read operation | Actual result |
|---|---|
| Pages projects | HTTP 403; connection lacks Pages Read/Write scopes |
| Workers subdomain | HTTP 403; connection lacks Workers Scripts Read/Write scopes |
| Tunnel inventory | Connector refused HTTP 403: no authorized visible inventory; an empty result does not prove no tunnels exist |
| Access applications | HTTP 403; API reports Access is not enabled |
| Zero Trust organization | HTTP 403; connection lacks Access organization scopes |
| Subscriptions | HTTP 403; this endpoint needs a billing-scoped API token, not the connected OAuth session |

Thus account-specific plan entitlements, usage and safe publishing permissions
could not be verified. Do not interpret successful identity lookup as deployment
authority. No credentials need to be copied into this repository or chat.

## Compatibility and cost

| Option | Fit and decision |
|---|---|
| Cloudflare Workers Static Assets / Pages | Suitable for compiled public Flutter files only. Current documented Workers Free limits are 20,000 files and 25 MiB per file. The tested build has 47 files, 45,779,916 bytes total, largest 7,229,467 bytes; it fits these file limits. Account quota/permissions are not verified. |
| Cloudflare Python Workers | Not accepted as a drop-in runtime for this native Rust subprocess, raster libraries, SQLite/photo filesystem and local authorization model. No port or database migration was attempted. |
| Cloudflare Containers | Native Linux software is plausible, but current pricing requires Workers Paid ($5/month plus usage) and provides no Free allocation. Not provisioned. Persistent storage compatibility would still require verification. |
| Tunnel + Access | Could use a separately sanitized, access-restricted demonstration on a persistent operator-owned host. Access is not enabled/authorized here and no independently persistent host is selected. No tunnel was opened. |
| Render Free web service | Reject for this unchanged persistence contract: its filesystem is ephemeral and Free services cannot attach persistent disks. Moving SQLite/photos to a different database/object service would be a separate, unreviewed migration. |
| Oracle Always Free Linux VM | Technically compatible with Python/native executables and persistent block storage if a qualifying account/shape/capacity is available. No Oracle connector or provisioned host is available in this task; eligibility/capacity are unverified. Idle resources may be reclaimed. ARM instances need independently built ARM binaries, not these x64 packages. No signup or paid resource was created. |

The supported fallback is the private Windows/Linux full-stack package and the
existing immutable 7Q local startup. See [artifacts](ARTIFACTS.md) and
[runbook](RUNBOOK.md). The container remains nonroot, loopback-only, one worker,
read-only root with a separately mounted persistent private data directory.
Its Dockerfile is buildable packaging, not a publicly authenticated application.

## Conditions before any hosted configuration

1. Select an authorized host with persistent disks and a tested stop/restart,
   backup and restore. Preserve separate workspace-photo and farm/source stores.
   The managed Codex workspace is not a guaranteed persistent public host.
2. Establish application authentication and ownership isolation, or use a
   completely separate sanitized read-only dataset. A shared Access login does
   not create per-farmer ownership in the current single-user service.
3. Create and verify deny-by-default Access policy **before** a tunnel route,
   validate Access JWT audience/issuer/signature at the origin or cloudflared,
   block origin bypass and test unauthorized access. Never rewrite headers to
   evade the current Host/Origin/loopback protections on the existing private app.
4. Keep browser tokens out of Flutter assets. If static and API origins differ,
   implement and test exact HTTPS origins, authenticated requests, cookies/CSRF,
   Web API base routes and source/photo authorization. Merely replacing
   `PLATFORM_URL` does not relocate same-origin NASA/Rust/workspace routes.
5. Build Flutter with the accepted HTTPS backend only after those contracts work:

   ```bash
   flutter build web --release --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run --dart-define=PLATFORM_URL=https://accepted-backend.example
   python ../scripts/finalize_offline.py build/web
   ```

   The domain above is a placeholder, not an available service. The existing
   local package intentionally rejects a build targeting another backend.
   Do not upload its loopback-configured JS as an operational hosted application.
6. For a new Cloudflare static application use the current `cf` CLI and its
   [agent instructions](https://developers.cloudflare.com/cf/agents/), or the
   authorized API. No Wrangler configuration was added to this project.
   Upload only the reviewed public build directory. Configure SPA fallback for
   navigation, keep `/api/*` out of static fallback/private caching, and use
   suitable cache headers for versioned assets and the service worker.
7. Through the actual HTTPS URL test polygon save/reopen, sources, real NASA/Rust,
   three strategies, photos, exact provenance, unauthorized requests, browser
   cache/offline semantics, and restart persistence. Record actual deployed
   source/image hashes and a verified URL only after success.

These conditions are unfulfilled hosting requirements, not a claim that a
production gateway or deployment has been implemented. No surprise paid resources
or relaxation of private endpoint safeguards is authorized by this document.

## Sources checked

- [Workers limits](https://developers.cloudflare.com/workers/platform/limits/)
- [Containers pricing](https://developers.cloudflare.com/containers/platform/pricing/)
- [Access self-hosted application and origin validation](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/)
- [cloudflared Access JWT enforcement](https://developers.cloudflare.com/tunnel/reference/origin-parameters/)
- [Render Free persistence restrictions](https://render.com/docs/free)
- [Oracle Always Free capacity and reclamation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
