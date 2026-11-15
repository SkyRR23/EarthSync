# Official forecasts, precipitation intervals and alerts

Actual `/points/42.0308,-93.6319` discovery maps Ames to **DMX / grid 73,69**,
forecast zone **IAZ048**, county **IAC169**, timezone **America/Chicago**.
The returned daily/hourly/grid/office/station/zone links are retained. A forecast
office is never inferred from a fixed office code in the UI.

Daily forecasts cover the next seven days; hourly view shows the next 24 hours.
Original temperatures/units and generated/updated/valid times survive conversion.
The separate grid adapter retains NWS quantitative precipitation totals over their
original intervals, plus native humidity and wind intervals. A six-hour rainfall
total is never divided into invented hourly amounts. Rain probability is not an
amount. Missing variables remain null. Expired forecasts are explicitly marked.

Alerts use the official geographically filtered active feed, retain original IDs,
authority, severity/urgency/certainty, areas, sent/effective/expiry/end times,
instructions, references and update/cancel status. Expired or cancelled messages
cannot remain active when a cached response ages. Issuer links open only the
official HTTPS NWS host.

A successful fresh empty feed says:
**“No active official alerts found at the last successful check.”**
A failed, stale, stopped-worker or disconnected check says:
**“Official alert status could not be verified.”**
There is no generated official warning or fabricated all-clear.

Open-Meteo is a separate model forecast: temperature, precipitation/probability,
humidity, wind and 0–1 cm modeled soil moisture. The automatic blend does not
identify its initialization/publication time; those fields stay unknown. Its
underlying models may overlap NOAA, so it is not independent station evidence.
Attribution is CC BY 4.0; the free endpoint is subject to non-commercial terms and
published quotas. A commercial installation must arrange the appropriate plan.

The original GFS temperature endpoint remains intact. The real-time extension
adds 12/24/48/72-hour temperature, humidity, 10 m wind components/speed and surface
precipitation. It validates operational NOAA identity, native levels, Kelvin,
reference/valid times, grid support and GRIB PDT 4.8 accumulation intervals. GFS
can publish overlapping precipitation intervals in one file; they are retained
separately, never added together. All GRIB Filter loops share a ten-second gap.
