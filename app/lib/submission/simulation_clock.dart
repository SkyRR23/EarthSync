import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';

class SimulationClock extends Notifier<DateTime> {
  @override
  DateTime build() {
    final raw = ref.read(prefsProvider)?.getString('simulation.date.v1');
    final saved = DateTime.tryParse(raw ?? '');
    if (saved != null && saved.year < DateTime.now().year) return saved;
    final today = DateTime.now();
    final year = ref.read(historicalWindowProvider).endYear;
    final maxDay = DateTime(year, today.month + 1, 0).day;
    return DateTime(year, today.month, today.day > maxDay ? maxDay : today.day);
  }
  void select(DateTime date) {
    state = DateTime(date.year, date.month, date.day);
    ref.read(prefsProvider)?.setString('simulation.date.v1', state.toIso8601String());
  }
}

final simulationClockProvider = NotifierProvider<SimulationClock, DateTime>(SimulationClock.new);

class SimulationBanner extends ConsumerWidget {
  const SimulationBanner({super.key, this.changeDate = true});
  final bool changeDate;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(simulationClockProvider);
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('SIMULATED TEST · NOT LIVE', style: TextStyle(fontWeight: FontWeight.bold)),
      Text('Simulation today: ${date.day}/${date.month}/${date.year}. Advice uses historical data and declared assumptions, not current field readings.'),
      if (changeDate) TextButton.icon(icon: const Icon(Icons.calendar_month), label: const Text('Change simulation date'), onPressed: () async {
        final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(1981), lastDate: DateTime(DateTime.now().year, 1, 1).subtract(const Duration(days: 1)));
        if (picked != null) ref.read(simulationClockProvider.notifier).select(picked);
      }),
    ])));
  }
}
