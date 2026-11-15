# Public Ames reference and station coverage

Public city reference: **42.0308, −93.6319**, Ames, Iowa. This is a reproducible
regional demonstration point, not an invented farm. Station metadata comes from
Iowa State University's official online-station GeoJSON service:
<https://mesonet.agron.iastate.edu/geojson/network.py?network=ISUSM&only_online=1>.

| Station | Official name | Latitude / longitude | Distance from reference |
|---|---|---|---:|
| AMFI4 | Ames – Finch Farm | 42.0621 / −93.6984 | 6.50 km |
| AHDI4 | Ames – Hinds Farm | 42.0628 / −93.6188 | 3.72 km |
| AKCI4 | Ames – Kitchen Farm | 41.9968 / −93.7031 | 6.99 km |

All three were marked online by actual metadata retrieval. This does not establish
that every sensor works. `NO_4INCH=1` is honored: a nominal 4-inch temperature is
withheld even if an export column happens to contain a number. Missing sensors
and QC-rejected cells are not filled. The Finch candidate is prioritized for Ames;
each returned measurement retains its own station, depth and timestamp.

Recent minute-table CSV is requested from the documented official service at
`/cgi-bin/request/isusm.py`, with `timeres=minute`, UTC and `qcflags=1`.
At most two recent hours are requested at startup; later requests overlap five
minutes for late QC corrections. Accepted rolling records are deduplicated by
station/variable/depth/time and capped at 2,880 cells. This is not a historical
backfill. Original Fahrenheit/inches/mph and converted °C/mm/m/s are retained.
Legacy VWC percent and SoilVue volumetric fractions use separate conversions.

The provider's null QC flag is exported as `M`; it means no additional flag is
supplied for a numeric QC value, not a missing numeric reading. Nonempty nonzero
flags are conservatively withheld. No unsupported frozen-sensor diagnosis is made.
The table is nominally minute resolution; exact accumulation/sensor intervals can
be unknown, especially for five-minute SoilVue records. They remain unknown rather
than being advertised as 60-second physical measurements.

UTC is stored internally; Iowa display additionally uses `America/Chicago`, with
both summer/winter offsets tested. See the evidence JSON for actual accepted
timestamps, variables, sensor depths and individual freshness states.
