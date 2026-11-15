# Authorized NASA numeric recovery

Actual official CMR discovery and authenticated asset reads were performed; see
the public-reference evidence summaries for exact times, versions and hashes.

| Product | Verified collection | Numeric path and acceptance |
|---|---|---|
| HLSL30_VI v2.0 | C3246892554-LPCLOUD | Official NDVI + original surface-reflectance Fmask COGs |
| HLSS30_VI v2.0 | C3246894861-LPCLOUD | Official NDVI + Fmask; accepted Ames NDVI **0.539**, acquisition **2026-10-22T17:12:07.203Z** |
| SPL4SMGP V008 | C3480440870-NSIDC_CPRD | Native HDF5 surface/root-zone cell, EASE-Grid 2.0 / EPSG:6933 |
| GPM_3IMERGHHE V07 | C2723758340-GES_DISC | Native HDF5 precipitation + quality index and half-hour bounds |

## Authentication defects and recovery

Unauthenticated HLS/SMAP/IMERG requests returned redirects to Earthdata Login.
The user supplied authorized credentials and completed GES DISC application
consent. `earthaccess==0.19.0`, environment strategy and `persist=False` obtain the
official authenticated session. Successful NASA asset redirects are **303 signed
CDN locations**, not necessarily failed login redirects. Those redirects now use
a separate unauthenticated session: bearer credentials never go to the CDN.
Only official NASA origins and supported HTTPS distribution redirects are allowed.
TLS verification stays enabled. Signed URLs, cookies and tokens never enter the
API response, provenance, files in Git or browser.

GES DISC initially returned **403 EULA Acceptance Failure**. After the user
approved the provider's account-consent page, actual IMERG range access and numeric
extraction succeeded. No registration, agreement or authorization bypass occurred.

## Bounded extraction and provenance

`RangeFile` exposes seekable bounded HTTP ranges to rasterio's opener and h5py.
No global HDF5 collection is downloaded. Default assets have a 16 MiB ceiling;
SMAP uses 256 KiB blocks with a 24 MiB ceiling. Each extraction session has a
64 MiB aggregate ceiling and 120-second deadline. Byte counts include rejected
HLS candidates. Native ETags/lengths protect multi-range consistency. SHA-256
receipts identify each downloaded **byte range**, explicitly not a full-file hash.
Chunks are temporary memory, not growing disk archives. Accepted cells, source
metadata and range hashes persist in private SQLite.

SMAP initially hit the bounded-reader ceiling with coarse blocks. Reducing block
size produced a successful **13,631,488-byte** cell read. The failed-only private
development attempt was cleared to exercise the corrected adapter; no accepted
record was changed or fabricated. Real surface/root-zone estimates were
0.3452495038509369 / 0.3515900671482086 m³/m³ for the **10 November 2026, 21:00–11 November 00:00
UTC** product interval, not current inside-field sensors.

HLS-VI has **−19999** fill and **0.0001** scale; the original reflectance reader's
−9999 contract is not incorrectly reused. NDVI/Fmask acquisition time, native
grid/CRS, pixel location, units/scale/nodata and conservative QA must agree.
Bits 0–5, high aerosol, fill and out-of-range pixels are rejected. The newest
Ames S30 and L30 candidates failed QA; a newer-looking cloud pixel was never
turned into a vegetation decline. Search is bounded to four candidates per
collection within 45 recent days. Rejected granule/revision/point keys are cached.
The accepted October acquisition is visibly delayed, never advertised as LIVE.

IMERG units are validated as mm/hr. Its native time bounds must span 1,800 seconds
and agree with CMR; multiplying the mean rate by 0.5 gives that interval's amount.
Native missingness, finite/range checks and nonmissing quality index are retained.
No unsupported high-quality threshold or field-accuracy claim is invented.

The inherited ORNL MODIS alternate timed out in the controlled recovery probe.
It is not a dependency or endlessly retried. NASA Harmony's attempted SMAP
collection URL returned a login HTML document, not numeric subset success; bounded
authorized native range extraction supplies the implemented alternative.

References: [HLS-VI guide](https://lpdaac.usgs.gov/documents/2088/HLS_VI_User_Guide_V2.pdf),
[SMAP V008 specification](https://nsidc.org/sites/default/files/documents/technical-reference/smap_l4_sm_psd_v17_for_l4sm_version_8.pdf),
[IMERG](https://gpm.nasa.gov/data/imerg). A future low-latency HLS service is not a dependency.
