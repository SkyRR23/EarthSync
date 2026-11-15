import '../../data/backend_response.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../../state/today.dart';
import '../../data/environment/forecast.dart';
import '../../design/components/logo.dart';
import 'home_shell.dart';

const farmerIntroKey = 'farmer_intro_v1';

/// Native first-run introduction, also available from Home for returning users.
class FarmerIntroduction extends ConsumerStatefulWidget {
  const FarmerIntroduction({super.key});
  @override
  ConsumerState<FarmerIntroduction> createState() => _IntroductionState();
}

class _IntroductionState extends ConsumerState<FarmerIntroduction> {
  int _step = 0;
  bool _saving = false;
  String? _error;
  static const _steps = [
    (Icons.agriculture, 'A helping hand for your farm',
      'See the weather, keep farm records and explore what to plant next.'),
    (Icons.map_outlined, 'Start with your field',
      'Choose your field on the map. Add crops and water details one step at a time. You can change your answers later.'),
    (Icons.chat_bubble_outline, 'Ask a question anytime',
      'Ask how to grow a crop without setting up a field. For questions about your own farm, EarthSync uses the details you have saved.'),
  ];

  Future<void> _finish(String route) async {
    setState(() { _saving = true; _error = null; });
    try {
      final prefs = ref.read(prefsProvider);
      if (prefs != null && !await prefs.setBool(farmerIntroKey, true)) {
        throw StateError('save failed');
      }
      if (mounted) context.go(route);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save your choice. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _steps[_step];
    final hasField = ref.watch(farmerDraftProvider).hasLocation;
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to EarthSync')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Center(child: EarthSyncLogo(size: 64)),
          const SizedBox(height: 32),
          Icon(item.$1, size: 80, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(item.$2, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Text(item.$3, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          Text('Step ${_step + 1} of ${_steps.length}'),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (_step + 1) / _steps.length),
          const SizedBox(height: 24),
          FilledButton(onPressed: _saving ? null : () {
            if (_step < _steps.length - 1) { setState(() => _step++); }
            else { _finish(hasField ? '/home' : '/setup/1'); }
          }, child: Text(_step < 2 ? 'Next' : hasField ? 'Open my farm' : 'Set up my field')),
          if (_step > 0) TextButton(onPressed: _saving ? null : () => setState(() => _step--), child: const Text('Back')),
          TextButton(onPressed: _saving ? null : () => _finish('/chat'), child: const Text('Ask about crops first')),
          TextButton(onPressed: _saving ? null : () => _finish('/home'), child: const Text('Explore first')),
          if (_error != null) Text(_error!),
          const Text('No account needed to get started. AI answers and fresh weather need an internet connection.'),
        ]),
      ))),
    );
  }
}

/// A task-oriented native home; the existing web HomeTab stays separate.
class FarmerStart extends ConsumerWidget {
  const FarmerStart({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(farmerDraftProvider);
    final forecast = ref.watch(forecastProvider);
    final tabs = HomeTabs.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('My farm today'), actions: [
        IconButton(tooltip: 'Help getting started', onPressed: () => context.push('/intro'), icon: const Icon(Icons.help_outline)),
        IconButton(tooltip: 'Notifications', onPressed: () => context.push('/notifications'), icon: const Icon(Icons.notifications_outlined)),
      ]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        Text(draft.hasLocation ? (draft.farmName?.trim().isNotEmpty == true ? draft.farmName! : 'Your field') : 'Let’s get started', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(draft.hasLocation ? 'Check the weather, plan your work and keep track of your field.' : 'Save your field to see local weather. You can ask general crop questions right away.'),
        const SizedBox(height: 16),
        if (!draft.hasLocation)
          FilledButton.icon(onPressed: () => context.push('/setup/1'), icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Set up my field')),
        if (draft.hasLocation && forecast.data != null)
          ForecastRainChart(days: forecast.data!.days, saved: forecast.failed, fetchedAt: forecast.data!.fetchedAt),
        if (draft.hasLocation && forecast.data == null)
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Weather for your field'),
            Text(forecast.loading ? 'Getting the latest forecast…' : backendMessage(forecast.errorCode ?? 'unreachable')),
            TextButton(onPressed: () => ref.read(forecastProvider.notifier).refresh(), child: const Text('Load weather')),
          ]))),
        const SizedBox(height: 12),
        _action(context, Icons.cloud_outlined, 'Check the weather', 'Rain and temperature for the coming days', () => tabs?.go(1)),
        _action(context, Icons.checklist, 'My tasks', 'Plan field visits and set reminders', () => tabs?.go(4)),
        _action(context, Icons.compare_arrows, 'Plan my next crops', 'Compare crop sequences and save your choice', () => context.push(draft.hasLocation ? '/rotation-plans' : '/setup/1')),
        _action(context, Icons.chat_bubble_outline, 'Ask EarthSync', 'General crop questions or help with your field', () => context.push('/chat')),
        _action(context, Icons.edit_note, 'My farm records', 'Keep observations, photos and notes', () => tabs?.go(3)),
        ExpansionTile(title: const Text('More field tools'), children: [
          ListTile(leading: const Icon(Icons.map_outlined), title: const Text('My field map'), onTap: () => tabs?.go(2)),
          ListTile(leading: const Icon(Icons.layers_outlined), title: const Text('Explore soil information'), onTap: () => context.push('/soil-map')),
          ListTile(leading: const Icon(Icons.history), title: const Text('Past seasons and evidence'), subtitle: const Text('Historical records, separate from today’s weather'), onTap: () => context.push('/science')),
          ListTile(leading: const Icon(Icons.info_outline), title: const Text('Sources and data details'), onTap: () => context.push('/sources')),
          ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Field details and settings'), onTap: () => context.push('/field-details')),
        ]),
      ])),
    );
  }

  Widget _action(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
    child: ListTile(contentPadding: const EdgeInsets.all(16), leading: Icon(icon, color: Theme.of(context).colorScheme.primary), title: Text(title), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap),
  );
}

/// Labelled forecast bars: missing readings stay missing, never become zero.
class ForecastRainChart extends StatelessWidget {
  const ForecastRainChart({super.key, required this.days, this.saved = false, required this.fetchedAt});
  final List<ForecastDay> days;
  final bool saved;
  final DateTime fetchedAt;
  @override
  Widget build(BuildContext context) {
    final shown = days.take(5).toList();
    final scale = shown.fold<double>(1, (max, d) => d.rainMm != null && d.rainMm! > max ? d.rainMm! : max);
    String date(DateTime d) => '${d.day}/${d.month}/${d.year}';
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Rain forecast · mm', style: Theme.of(context).textTheme.titleLarge),
      Text('${saved ? 'Saved forecast' : 'Forecast retrieved'} ${date(fetchedAt.toLocal())} · Open-Meteo'),
      const SizedBox(height: 12),
      if (shown.isEmpty) const Text('No daily forecast is available.'),
      for (final day in shown) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Semantics(
        label: '${date(day.date)}: ${day.rainMm == null ? 'rain unknown' : '${day.rainMm!.toStringAsFixed(1)} millimetres of rain forecast'}',
        child: ExcludeSemantics(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${date(day.date)} · ${day.rainMm?.toStringAsFixed(1) ?? 'Unknown'}${day.rainMm == null ? '' : ' mm'}'),
          Text('Temperature: ${day.minC?.round() ?? '?'}–${day.maxC?.round() ?? '?'} °C'),
          if (day.rainMm != null) LinearProgressIndicator(value: (day.rainMm! / scale).clamp(0.0, 1.0), minHeight: 10),
          if (day.rainMm == null) const Text('No accepted rainfall value'),
        ])),
      )),
      const SizedBox(height: 8),
      const Text('Longer bars mean more rain is forecast. Predictions may change; these are not measurements from your field.'),
    ])));
  }
}
