import '../data/models/field_analysis.dart';
import 'historical_reference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/environment/nasa_power_client.dart';
import '../state/providers.dart';
import 'simulation_clock.dart';

class SimulationWeatherPage extends ConsumerWidget {
  const SimulationWeatherPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Historical weather context')),
    body: ListView(padding: const EdgeInsets.all(20), children: const [SimulationBanner(), HistoricalWeatherSummary()]),
  );
}

class HistoricalWeatherSummary extends ConsumerWidget {
  const HistoricalWeatherSummary({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(simulationClockProvider);
    final state = ref.watch(analysisProvider);
    final window = ref.watch(historicalWindowProvider);
    final climate = state is AnalysisReady && window.startYear == date.year && window.endYear == date.year ? state.analysis.climateSummary : null;
    final usingReference = ref.watch(referenceChoiceProvider);
    final reference = ref.watch(historicalReferenceProvider).value;
    final rows = usingReference ? <MonthlyClimate>[for (final m in reference?['months'] as List? ?? []) if (m['year'] == date.year) MonthlyClimate(year: m['year'] as int, month: m['month'] as int, rainMm: (m['rain_mm'] as num?)?.toDouble())] : climate?.months ?? <MonthlyClimate>[];
    final month = rows.where((m) => m.year == date.year && m.month == date.month).firstOrNull;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('NASA historical context · ${date.month}/${date.year}', style: Theme.of(context).textTheme.titleLarge),
      const Text('Monthly modeled context, not the weather measured on this particular day. No daily rain, heat or wind is inferred from a monthly average.'),
      Text('Rainfall total: ${month?.rainMm?.toStringAsFixed(1) ?? 'Unknown'}${month?.rainMm == null ? '' : ' mm'}'),
      Text('Mean temperature: ${month?.tempMeanC?.toStringAsFixed(1) ?? 'Unknown'}${month?.tempMeanC == null ? '' : ' °C'}'),
      if (rows.isNotEmpty) ...[
        const Divider(),
        const Text('Historical rainfall through the year · mm'),
        for (final row in rows) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${row.month}/${row.year ?? date.year} · ${row.rainMm?.toStringAsFixed(1) ?? 'Unknown'}${row.rainMm == null ? '' : ' mm'}'),
          if (row.rainMm != null) LinearProgressIndicator(value: (row.rainMm! / rows.fold<double>(1, (a, b) => (b.rainMm ?? 0) > a ? b.rainMm! : a)).clamp(0.0, 1.0)),
        ])),
        Text(usingReference ? 'Archived NASA POWER reference: Yangon 16.85, 96.15 · ${date.year}. This is reference-location data, not a measurement from your saved field.' : 'Source: ${climate?.sourceId} · period ${climate?.period}'),
      ],
      if (!usingReference && state is AnalysisFailed) Text('The historical-data service could not load this year. Your teammate needs to check the hosted backend. ${state.error.message}'),
      if (!usingReference) FilledButton.icon(onPressed: state is AnalysisRunning ? null : () {
        ref.read(historicalWindowProvider.notifier).setWindow(HistoricalWindow(startYear: date.year, startMonth: 1, endYear: date.year, endMonth: 12));
        final draft = ref.read(farmerDraftProvider);
        if (!draft.hasLocation) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose your field before loading its historical data.'))); return; }
        ref.read(analysisProvider.notifier).run(draft.toInput());
      }, icon: const Icon(Icons.download), label: Text(state is AnalysisRunning ? 'Loading historical year…' : 'Load ${date.year} NASA data')),
      TextButton(onPressed: () async {
        if (usingReference) { ref.read(referenceChoiceProvider.notifier).select(false); return; }
        final accepted = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(title: const Text('Use the included Yangon reference?'), content: const Text('This offline NASA archive covers 2016–2025 at 16.85, 96.15. It supplies dated rainfall and modeled root wetness, not temperatures or wind. It will be simulation reference context, not data from your saved field.'), actions: [TextButton(onPressed: () => Navigator.pop(dialog,false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog,true), child: const Text('Use reference data'))]));
        if (accepted == true && context.mounted) ref.read(referenceChoiceProvider.notifier).select(true);
      }, child: Text(usingReference ? 'Use my field’s loaded historical data instead' : 'Use included offline Yangon reference (2016–2025)')),
    ])));
  }
}
