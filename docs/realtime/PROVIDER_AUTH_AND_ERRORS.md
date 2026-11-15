# Provider authentication and error contract

Initial cloud probes failed **at the managed proxy with 403**, before reaching
the providers. The user changed the running environment's network policy; the
observed revision was rechecked and fresh official requests then succeeded.
This is distinct from a NASA authorization denial or provider HTTP failure.

The backend categorizes authentication required, authorization denied, rate limit,
provider outage, timeout/network/TLS failure, unsupported endpoint/product,
unpublished data, geographic non-coverage, missing sensor, invalid units/data,
expired data, byte-budget rejection and scientific QA rejection. A failed refresh
retains the last accepted record and its original time, with a stale state.
Failed requests do not advance successful-check timestamps or establish all-clear.

Conditional requests honor ETag/Last-Modified, HTTP cache lifetime and Retry-After.
Per-host locks prevent concurrent JSON requests to a provider. Transient retries
start at 60 seconds and back off; permanent/auth/QA failures use source cadence.
Both per-source next-check times and JSON-provider backoff persist across restart.
Manual refresh schedules due work; it does not bypass these rules.

`EARTHDATA_TOKEN` is backend-only. Use a cloud environment secret or a protected
local process environment, not a committed `.env`, URL, browser field, command-line
argument, screenshot or log. `earthaccess` does not persist a netrc file. The token
shared during this chat was used only for the explicitly authorized official
NASA requests and must be revoked/replaced after testing. Temporary credential
files are excluded and removed when the test processes stop.

NWS needs the identifying User-Agent, not a secret. Open-Meteo's free endpoint
needs no key within its terms. Iowa metadata/data are official public services.
The original platform loopback Host/Origin/owner boundaries and separate photo
workspace token remain in force; no public authenticated service is introduced.

The first running Open-Meteo Ames refresh returned a genuine provider outage.
It remained unavailable while respecting the recorded retry schedule. The live
matrix distinguishes this from earlier successful five-location requests and
records any later recovery. No captured forecast is substituted during outages.
