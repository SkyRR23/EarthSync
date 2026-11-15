# Ames/Iowa test cases

Any coordinates/profile/input created by the software smoke tests are explicitly
synthetic and supply no agronomic ground truth.

| Case | Expected result |
|---|---|
| Maize, `US-IA`, question `soil sampling` | Iowa State source dossier; six inches retained as sampling context, no suitability |
| Maize, `Iowa` or unknown region ID | No exact documented scope; do not substitute Myanmar/tropical references |
| Rice with no region | Original global/regional references retain their own scope, not Iowa applicability |
| Any crop with an unreviewed cultivar filter | No matching cultivar; no fallback from unknown scope |
| Saved SoilGrids pH, 0–5 cm, nominal 250 m | Modeled regional category; never laboratory or full-field truth |
| Lab sample pH at 0–15 cm in water | User-confirmed sample transcription; do not directly reconcile incompatible model depth/method |
| Farmer report of standing water | Attributed report; not quantified flood exposure or tolerance |
| Brown soil image | No chemical measurement; default vision unavailable |
| Sesame stage source | Retain 110-day sum and stated 100; no averaging or rescaling |
| Crop comparison | Source evidence and unresolved review questions; no percentage or rank |

Synthetic HTTP and browser fixtures exercise these boundaries. No field trial,
local Iowa crop recommendation, USDA threshold import or Iowa agronomist approval
is claimed.
