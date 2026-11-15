# Unused real-time path

The Android demo uses an explicitly selected historical simulation date. The
initial day/month follows the actual calendar, within the chosen historical data
year. Source years remain visible; no historical record is relabelled as live.

Live forecast, recent-weather and satellite requests are not the main demo path.
They depend on a separately deployed service and upstream APIs. Phone screenshots
showed those requests failing; repository source does not establish deployed API
health. Service availability/configuration is unresolved with the teammate who
manages Cloud Run. That is the main reason this version keeps real-time features
separate and unused in the simulation.

The retained implementations are in `data/environment/forecast.dart`,
`data/environment/recent_conditions.dart`, `features/home/weather_tab.dart` and
`evidence/features/realtime/`. They remain in their original paths for compatibility
and a later opt-in restoration; this folder is not imported by the application.
Do not silently enable them as a substitute for historical simulation data.
