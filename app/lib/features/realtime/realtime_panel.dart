import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../state/platform_provider.dart';

String realtimeCopy(BuildContext context, String text) {
  const my = {
    'Real-time EarthSync': 'လက်ရှိအချက်အလက် EarthSync',
    'Refresh': 'ပြန်လည်ရယူရန်',
    'Current station observations': 'စခန်းမှ နောက်ဆုံးတိုင်းတာချက်များ',
    'Official forecasts': 'တရားဝင် မိုးလေဝသခန့်မှန်းချက်များ',
    'Official alerts': 'တရားဝင် သတိပေးချက်များ',
    'Global model forecast': 'ကမ္ဘာလုံးဆိုင်ရာ မော်ဒယ်ခန့်မှန်းချက်',
    'Next 24 hours': 'လာမည့် ၂၄ နာရီ',
    'Next 7 days': 'လာမည့် ၇ ရက်',
    'Hourly view': 'နာရီအလိုက်',
    'Daily view': 'နေ့အလိုက်',
    'Source diagnostics': 'အချက်အလက်ရင်းမြစ် အခြေအနေ',
    'Open monitoring dashboard': 'လက်ရှိအချက်အလက် စာမျက်နှာဖွင့်ရန်',
    'No accepted measurements': 'လက်ခံအတည်ပြုထားသော တိုင်းတာချက်မရှိပါ',
    'Selected field': 'ရွေးထားသောလယ်ယာ',
    'Public reference location': 'အများပြည်သူသုံး ရည်ညွှန်းနေရာ',
  };
  return Localizations.localeOf(context).languageCode == 'my'
      ? my[text] ?? text
      : text;
}

class RealtimeScreen extends StatelessWidget {
  const RealtimeScreen({super.key, this.initialField = false});
  final bool initialField;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(realtimeCopy(context, 'Real-time EarthSync'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: RealtimePanel(initialField: initialField),
        ),
      ),
    ),
  );
}

/// Polls only the private FastAPI cache. No browser holds provider credentials.
class RealtimePanel extends ConsumerStatefulWidget {
  const RealtimePanel({
    super.key,
    this.compact = false,
    this.fieldOnly = false,
    this.initialField = false,
  });
  final bool compact, fieldOnly, initialField;
  @override
  ConsumerState<RealtimePanel> createState() => _RealtimePanelState();
}

class _RealtimePanelState extends ConsumerState<RealtimePanel> {
  static const prefix = '/api/platform/v1';
  Timer? _timer;
  Map<String, dynamic>? _snapshot;
  String _location = 'ames';
  String? _error, _path;
  bool _busy = false, _daily = false;
  DateTime? _displayedAt, _manualAt;
  int? _requestMs;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialField || widget.fieldOnly) _location = 'field';
  }

  @override
  void dispose() {
    _revision++;
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool manual = false, bool activate = false}) async {
    final client = ref.read(platformFarmClientProvider);
    final path = _path;
    if (client == null || path == null || _busy) return;
    final revision = _revision;
    setState(() => _busy = true);
    final watch = Stopwatch()..start();
    try {
      if ((manual || activate) && _location != 'field') {
        await client.transport.request(
          'POST',
          '$prefix/realtime/$_location/refresh',
          expectedStatus: 202,
        );
      }
      final raw = await client.transport.request(
        'GET',
        path,
        expectedStatus: 200,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _snapshot = Map<String, dynamic>.from(raw as Map);
        _error = null;
        _displayedAt = DateTime.now().toUtc();
        _requestMs = watch.elapsedMilliseconds;
        if (manual) _manualAt = DateTime.now();
      });
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(
          () => _error =
              'Local monitoring service could not be reached. Previously displayed data may be stale; official alert status could not be verified.',
        );
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _busy = false);
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 15), () => _load());
      }
    }
  }

  void _select(String value) {
    _timer?.cancel();
    setState(() {
      _location = value;
      _path = null;
      _snapshot = null;
      _error = null;
      _manualAt = null;
      _busy = false;
      _revision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    String tr(String s) => realtimeCopy(context, s);
    final client = ref.watch(platformFarmClientProvider);
    final farm = ref.watch(platformFarmProvider).value;
    if (widget.fieldOnly && _location != 'field') _location = 'field';
    final path = _location == 'field'
        ? farm == null
              ? null
              : '$prefix/farms/${farm.id}/realtime'
        : '$prefix/realtime/$_location';
    if (_path != path) {
      _path = path;
      _snapshot = null;
      _revision++;
      _busy = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(activate: !widget.fieldOnly);
      });
    }
    final sources = _snapshot?['sources'] as Map? ?? {};
    final location = _snapshot?['location'] as Map?;
    final canRefresh =
        !_busy &&
        (_manualAt == null ||
            DateTime.now().difference(_manualAt!).inSeconds >= 60);
    return Card(
      semanticContainer: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  tr('Real-time EarthSync'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                OutlinedButton.icon(
                  onPressed: canRefresh && client != null && path != null
                      ? () => _load(manual: true)
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('Refresh')),
                ),
                if (widget.compact)
                  TextButton(
                    onPressed: () => context.push(
                      _location == 'field' ? '/realtime?field=1' : '/realtime',
                    ),
                    child: Text(tr('Open monitoring dashboard')),
                  ),
              ],
            ),
            if (!widget.fieldOnly)
              DropdownButtonFormField<String>(
                initialValue: _location,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr('Public reference location'),
                ),
                items: [
                  if (farm != null || _location == 'field')
                    DropdownMenuItem(
                      value: 'field',
                      child: Text(tr('Selected field')),
                    ),
                  for (final entry in const {
                    'ames': 'Ames, Iowa',
                    'crawfordsville': 'Crawfordsville, Iowa',
                    'davis': 'Davis, California',
                    'yangon': 'Yangon, Myanmar',
                    'mandalay': 'Mandalay, Myanmar',
                  }.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _select(value);
                },
              ),
            const SizedBox(height: 12),
            const Text(
              'Latest published evidence, with source-specific delays. Stations are nearby points; satellite and soil grids are regional context. Monitoring runs only while the backend is running.',
            ),
            if (location != null)
              Text(
                '${location['name']} · ${location['lat']}, ${location['lon']} · ${location['timezone']}',
              ),
            if (client == null)
              const Text(
                'Connect the local evidence platform to enable monitoring. Build with PLATFORM_URL pointing to the loopback backend.',
              ),
            if (_location == 'field' && farm == null)
              const Text(
                'Connect the selected confirmed field to the private service first.',
              ),
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Reading local monitoring cache',
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_snapshot != null) ...[
              Text(
                'Automatic cache check: 15 s · backend monitoring: ${_snapshot!['worker_running'] == true ? 'running' : 'stopped'}',
              ),
              Text(
                'Displayed at $_displayedAt UTC · measured local request $_requestMs ms',
              ),
              for (final entry in const {
                'iowa_station': 'Current station observations',
                'nws_alerts': 'Official alerts',
                'nws_forecast': 'Official forecasts',
                'nws_grid': 'Official rainfall forecast intervals',
                'open_meteo': 'Global model forecast',
                'noaa_gfs': 'NOAA GFS forecast samples',
                'nasa_catalog': 'Latest NASA catalog acquisitions',
                'imerg': 'Latest NASA regional precipitation estimate',
                'smap':
                    'Latest available regional NASA SMAP soil-moisture estimate',
                'hls_ndvi': 'Latest quality-accepted HLS NDVI acquisition',
              }.entries)
                _source(
                  context,
                  entry.key,
                  tr(entry.value),
                  Map<String, dynamic>.from(sources[entry.key] as Map? ?? {}),
                ),
              if (!widget.compact) ...[
                const Divider(),
                const Text(
                  'NASA environment · latest accepted numerical products',
                ),
                for (final entry
                    in (_snapshot!['satellite_status'] as Map).entries)
                  Text('${entry.key}: ${entry.value}'),
                const Text(
                  'SoilGrids modeled pH, NASA POWER climate reference, GFS snapshots and dated GIBS true color remain in Field → Map & environment. True color and discovery metadata are not NDVI. Numeric satellite cards require authorized access and native scientific checks.',
                ),
                TextButton(
                  onPressed: () => context.push('/field'),
                  child: const Text('Field map & environment'),
                ),
                TextButton(
                  onPressed: () => context.push('/rotations'),
                  child: const Text(
                    'Review baseline, Alternative A and Alternative B',
                  ),
                ),
              ],
              Text(_snapshot!['scientific_status'] as String),
            ],
          ],
        ),
      ),
    );
  }

  Widget _source(
    BuildContext context,
    String id,
    String title,
    Map<String, dynamic> source,
  ) {
    final data = source['data'] as Map?;
    final stale = _error != null || source['status'] != 'FRESH';
    final status = _error != null
        ? 'CACHED DISPLAY · CONNECTION FAILED'
        : source['status'];
    final contents = <Widget>[
      Text('$title · $status', style: Theme.of(context).textTheme.titleMedium),
      Text('${source['source']} · ${source['data_type']}'),
      Text(
        'Last successful check: ${source['last_success_at'] ?? 'Unknown'}\nLast attempt: ${source['last_attempt_at'] ?? 'Not yet checked'}',
      ),
      if (source['error'] != null) Text('Reason: ${source['error']}'),
      if (id == 'nws_alerts')
        Text(
          stale
              ? 'Official alert status could not be verified.'
              : source['message'] as String? ??
                    'Official alert status could not be verified.',
        ),
    ];
    if (data != null) {
      if (id == 'iowa_station') {
        final stations = data['stations'] as List? ?? [];
        for (final station in stations) {
          contents.add(
            Text(
              '${station['id']} · ${station['name']} · ${station['distance_km']} km from reference · metadata online: ${station['online']}',
            ),
          );
        }
        final measurements = data['measurements'] as List? ?? [];
        if (measurements.isEmpty) {
          contents.add(Text(realtimeCopy(context, 'No accepted measurements')));
        }
        for (final m in measurements.take(widget.compact ? 8 : 120)) {
          contents.add(
            Text(
              '${m['station_id']} · ${m['variable']}${m['depth_cm'] == null ? '' : ' at ${m['depth_cm']} cm'}: ${(m['value'] as num).toStringAsFixed(2)} ${m['unit']} · ${stale ? 'STALE' : m['status']}\nObserved ${m['observed_at']} · local ${m['observed_local']} · accumulation interval ${m['interval_seconds'] ?? 'Unknown'} · QC ${m['quality_flag']}',
            ),
          );
        }
      } else if (id == 'nws_alerts') {
        for (final alert in data['alerts'] as List? ?? []) {
          contents.add(
            SelectableText(
              '${alert['event']} · ${alert['severity']} · ${alert['urgency']} · ${alert['certainty']}\n${alert['headline']}\n${alert['areaDesc']}\nIssued ${alert['sent']} · expires ${alert['expires']}\n${alert['description']}\n${alert['instruction'] ?? ''}\nIssuer: ${alert['senderName']}\n${alert['source_url']}',
            ),
          );
          final url = Uri.tryParse(alert['source_url'] as String? ?? '');
          if (url != null &&
              url.scheme == 'https' &&
              url.host == 'api.weather.gov') {
            contents.add(
              TextButton(
                onPressed: () async {
                  try {
                    final opened = await launchUrl(
                      url,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not open the official source. Use the displayed URL.',
                          ),
                        ),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not open the official source. Use the displayed URL.',
                          ),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Open official alert source'),
              ),
            );
          }
        }
      } else if (id == 'nws_forecast') {
        contents.add(
          Text(
            'Office: ${data['office']} · generated ${data['issued_at'] ?? 'Unknown'} · updated ${data['updated_at'] ?? 'Unknown'}',
          ),
        );
        if (!widget.compact) {
          contents.add(
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(realtimeCopy(context, 'Hourly view')),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(realtimeCopy(context, 'Daily view')),
                ),
              ],
              selected: {_daily},
              onSelectionChanged: (values) =>
                  setState(() => _daily = values.single),
            ),
          );
        }
        contents.add(
          Text(realtimeCopy(context, _daily ? 'Next 7 days' : 'Next 24 hours')),
        );
        for (final period
            in (data[_daily ? 'daily' : 'hourly'] as List? ?? []).take(
              widget.compact
                  ? 3
                  : _daily
                  ? 14
                  : 24,
            )) {
          contents.add(
            Text(
              '${period['start']} → ${period['end']} · ${(period['temperature_c'] as num).toStringAsFixed(1)} °C · rain probability ${period['precipitation_probability_pct'] ?? 'Unknown'}% · humidity ${period['relative_humidity_pct'] ?? 'Unknown'}% · wind ${period['wind']} ${period['wind_direction']}\n${period['summary']}',
            ),
          );
        }
      } else if (['imerg', 'smap', 'hls_ndvi'].contains(id)) {
        contents.add(
          Text(
            '${data['product']} v${data['version']}\nAcquired ${data['acquired_start']} → ${data['acquired_end']}\n${data['granule_id']}',
          ),
        );
        for (final m in data['measurements'] as List? ?? []) {
          contents.add(
            Text(
              '${m['variable']}${m['depth_cm'] == null ? '' : ' · 0–${m['depth_cm']} cm model layer'}: ${m['value']} ${m['unit']}',
            ),
          );
        }
        contents.add(
          Text(
            'Resolution: ${data['resolution']}. Missing values, units and native quality flags checked. Independent field accuracy has not been established.',
          ),
        );
        if (data['quality_index'] != null) {
          contents.add(
            Text(
              'Provider precipitation quality index: ${data['quality_index']} (not a field-accuracy score)',
            ),
          );
        }
      } else if (id == 'noaa_gfs') {
        contents.add(
          Text(
            'Initialized ${data['model_initialized_at']} · publication time unknown',
          ),
        );
        for (final row in data['records'] as List? ?? []) {
          contents.add(
            Text(
              '${row['valid_at']} · ${row['temperature_c']} °C · RH ${row['relative_humidity_pct']}% · wind ${row['wind_speed_ms']} m/s\nForecast precipitation ${row['precipitation_mm']} mm over ${row['precipitation_start']} → ${row['precipitation_end']}',
            ),
          );
        }
      } else if (id == 'nws_grid') {
        contents.add(
          Text('Office: ${data['office']} · updated ${data['updated_at']}'),
        );
        for (final row
            in ((data['variables'] as Map?)?['quantitativePrecipitation']
                        as List? ??
                    [])
                .take(widget.compact ? 2 : 30)) {
          contents.add(
            Text(
              '${row['start']} → ${row['end']} · ${row['value'] ?? 'Unknown'} mm total forecast precipitation over this whole interval',
            ),
          );
        }
      } else if (id == 'nasa_catalog') {
        for (final product in data['products'] as List? ?? []) {
          contents.add(
            Text(
              '${product['product']} v${product['version']} · ${product['status']}\nAcquired ${product['acquired_start'] ?? 'Unknown'} → ${product['acquired_end'] ?? 'Unknown'}\nCatalog revision ${product['catalog_revision_at'] ?? 'Unknown'} · numeric observation: ${product['numeric_observation']}',
            ),
          );
        }
      } else if (id == 'open_meteo') {
        contents.add(
          Text(
            '${data['model']}\nModel initialization: ${data['model_initialization_at'] ?? 'Unknown'}',
          ),
        );
        for (final row in (data['hourly'] as List? ?? []).take(
          widget.compact ? 3 : 24,
        )) {
          contents.add(
            Text(
              '${row['start']} · ${row['temperature_2m'] ?? 'Unknown'} °C · previous-hour rainfall forecast ${row['precipitation'] ?? 'Unknown'} mm · probability ${row['precipitation_probability'] ?? 'Unknown'}% · RH ${row['relative_humidity_2m'] ?? 'Unknown'}% · wind ${row['wind_speed_10m'] ?? 'Unknown'} m/s · modeled soil moisture (0–1 cm) ${row['soil_moisture_0_to_1cm'] ?? 'Unknown'} m³/m³',
            ),
          );
        }
      }
      if (!widget.compact) {
        contents.add(
          ExpansionTile(
            title: Text(realtimeCopy(context, 'Source diagnostics')),
            childrenPadding: const EdgeInsets.all(8),
            children: [
              Text(
                'Resolution: ${data['resolution']}\nPublication time: ${data['publication_at'] ?? 'Unknown'}\nCache age: ${source['cache_age_seconds']} s · next check: ${source['next_check_at']}\nProcessing: ${source['processing_ms']} ms',
              ),
              for (final receipt in data['provenance'] as List? ?? [])
                SelectableText(
                  '${receipt['url']}\nSHA-256 ${receipt['sha256']}\nRetrieved ${receipt['retrieved_at']} · HTTP ${receipt['http_status']} · ${receipt['request_ms']} ms',
                ),
            ],
          ),
        );
      }
    }
    contents.add(
      Text(source['limitations'] as String? ?? 'No data substituted.'),
    );
    if (widget.compact) {
      final measurements = data?['measurements'] as List? ?? [];
      final first = measurements.isEmpty ? null : measurements.first;
      return ExpansionTile(
        title: Text('$title · $status'),
        subtitle: Text(
          first == null
              ? 'Last successful check: ${source['last_success_at'] ?? 'Unknown'}'
              : '${first['station_id']} · ${first['value']} ${first['unit']} · ${first['observed_at']}',
        ),
        children: contents,
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: contents,
        ),
      ),
    );
  }
}
