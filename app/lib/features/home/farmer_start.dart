import '../../submission/simulation_weather.dart';
import '../../submission/simulation_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
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
    ('Start with your field.',
      'Save a place, add your crops, and keep the next step in view.'),
    ('A plan with a reason.',
      'Compare your next three seasons. See what to consider instead, and why.'),
    ('Look. Note. Follow up.',
      'Record what you see. Get a practical next check, even without online AI.'),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero : const Duration(milliseconds: 260);
    return Scaffold(
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 8, 16, 0), child: Row(children: [
            IconButton(tooltip: 'Previous step', onPressed: _step == 0 || _saving ? null : () => setState(() => _step--), icon: const Icon(Icons.arrow_back)),
            const EarthSyncLogo(size: 30),
            const SizedBox(width: 8),
            Expanded(child: Text('EarthSync', style: theme.textTheme.titleMedium)),
            TextButton(onPressed: _saving ? null : () => _finish('/home'), child: const Text('Explore')),
          ])),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: AnimatedSwitcher(duration: motion,
              transitionBuilder: (child, animation) => FadeTransition(opacity: animation,
                child: SlideTransition(position: Tween<Offset>(begin: const Offset(.04, 0), end: Offset.zero).animate(animation), child: child)),
              child: Column(key: ValueKey(_step), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _IntroductionPreview(step: _step),
                const SizedBox(height: 28),
                Text(item.$1, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.15)),
                const SizedBox(height: 12),
                Text(item.$2, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
              ]),
            ),
          )),
          Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _steps.length; i++) AnimatedContainer(
                duration: motion, margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _step ? 22 : 6, height: 6,
                decoration: BoxDecoration(color: i == _step ? colors.primary : colors.outlineVariant, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 12),
              Text('${_step + 1} / ${_steps.length}', style: theme.textTheme.bodySmall),
            ]),
            const SizedBox(height: 20),
            FilledButton(onPressed: _saving ? null : () {
              if (_step < _steps.length - 1) { setState(() => _step++); }
              else { _finish(hasField ? '/home' : '/setup/1'); }
            }, child: Text(_step < 2 ? 'Continue' : hasField ? 'Open my farm' : 'Set up my field')),
            if (_step == 2) TextButton(onPressed: _saving ? null : () => _finish('/chat'), child: const Text('Ask a crop question first')),
            if (_error != null) Text(_error!),
            const SizedBox(height: 12),
            Text('Historical simulation · not live conditions', textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: colors.primary)),
            const SizedBox(height: 4),
            Text('No sign-in. Core demo works offline. Maps and online AI need internet.',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ])),
        ]),
      ))),
    );
  }
}

/// Small product previews give the introduction concrete meaning without
/// decorative stock graphics or invented weather/health readings.
class _IntroductionPreview extends StatelessWidget {
  const _IntroductionPreview({required this.step});
  final int step;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(
      color: colors.primaryContainer.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: colors.primary.withValues(alpha: .15)),
    ), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Icon(step == 0 ? Icons.map_outlined : step == 1 ? Icons.compare_arrows : Icons.edit_note, color: colors.primary),
        const SizedBox(width: 8), Expanded(child: Text(step == 0 ? 'Your field, at a glance' : step == 1 ? 'Three seasons ahead' : 'A note becomes a next step', style: theme.textTheme.titleMedium)),
      ]),
      const SizedBox(height: 16),
      if (step == 0) ...[
        _previewRow(context, Icons.umbrella_outlined, 'Weather history', 'Dated rain and seasonal context'),
        _previewRow(context, Icons.checklist, 'Field checks', 'What to look at next'),
        _previewRow(context, Icons.spa_outlined, 'Crop plans', 'Options with reasons'),
      ] else if (step == 1) ...[
        Text('Example sequence', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final (i, crop) in const ['Rice', 'Mung bean', 'Sesame'].indexed)
          Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
            CircleAvatar(radius: 13, backgroundColor: colors.primary, foregroundColor: colors.onPrimary, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 12), Text(crop, style: theme.textTheme.bodyLarge),
          ])),
        const SizedBox(height: 8),
        Text('Compare options → read the reasons → choose', style: theme.textTheme.bodySmall),
      ] else ...[
        _previewRow(context, Icons.edit_note, '“Insects on my leaves”', 'Your observation'),
        const Padding(padding: EdgeInsets.only(left: 12), child: Icon(Icons.south, size: 18)),
        _previewRow(context, Icons.search, 'Check both sides of the leaves', 'A next check, not a diagnosis'),
        const SizedBox(height: 8),
        Text('Keep the observation and follow up.', style: theme.textTheme.bodySmall),
      ],
    ]));
  }

  Widget _previewRow(BuildContext context, IconData icon, String title, String subtitle) =>
    Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 20), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ])),
      ]));
}

/// A task-oriented native home; the existing web HomeTab stays separate.
class FarmerStart extends ConsumerWidget {
  const FarmerStart({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(farmerDraftProvider);
    final tabs = HomeTabs.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('My farm simulation'), actions: [
        IconButton(tooltip: 'Help getting started', onPressed: () => context.push('/intro'), icon: const Icon(Icons.help_outline)),
        IconButton(tooltip: 'Notifications', onPressed: () => context.push('/notifications'), icon: const Icon(Icons.notifications_outlined)),
      ]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        const SimulationBanner(compact: true),
        Text(draft.hasLocation ? (draft.farmName?.trim().isNotEmpty == true ? draft.farmName! : 'Your field') : 'Let’s get started', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(draft.hasLocation ? 'Start with a field check or compare crop rotations.' : 'Save your field to see local weather. You can ask general crop questions right away.'),
        const SizedBox(height: 16),
        if (!draft.hasLocation)
          FilledButton.icon(onPressed: () => context.push('/setup/1'), icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Set up my field')),
        const SizedBox(height: 12),
        _action(context, Icons.checklist, 'Suggested checks', 'See what to inspect on this simulation day', () => tabs?.go(4)),
        _action(context, Icons.compare_arrows, 'Plan my next crops', 'Compare crop sequences and save your choice', () => context.push(draft.hasLocation ? '/rotation-plans' : '/setup/1')),
        if (draft.hasLocation) const HistoricalWeatherSummary(compact: true),
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
    child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), leading: Icon(icon, color: Theme.of(context).colorScheme.primary), title: Text(title), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap),
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
