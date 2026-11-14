import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/environment/nasa_power_client.dart';
import '../../design/components/scenario.dart' show monthNames;
import '../../state/providers.dart';

class HistoricalWindowSelector extends ConsumerWidget {
  const HistoricalWindowSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(historicalWindowProvider);
    void update({int? sy, int? sm, int? ey, int? em}) => ref
        .read(historicalWindowProvider.notifier)
        .setWindow(
          HistoricalWindow(
            startYear: sy ?? w.startYear,
            startMonth: sm ?? w.startMonth,
            endYear: ey ?? w.endYear,
            endMonth: em ?? w.endMonth,
          ),
        );
    Widget month(String label, int value, ValueChanged<int> change) => Expanded(
      child: DropdownButtonFormField<int>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var m = 1; m <= 12; m++)
            DropdownMenuItem(value: m, child: Text(monthNames[m - 1])),
        ],
        onChanged: (v) {
          if (v != null) change(v);
        },
      ),
    );
    Widget year(String label, int value, ValueChanged<int> change) => Expanded(
      child: DropdownButtonFormField<int>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var y = DateTime.now().toUtc().year; y >= 1981; y--)
            DropdownMenuItem(value: y, child: Text('$y')),
        ],
        onChanged: (v) {
          if (v != null) change(v);
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('NASA historical climate window (LST)'),
        const Text(
          'Choose completed months, up to 24. This is separate from your planting month.',
        ),
        TextButton(
          onPressed: () {
            final year = DateTime.now().toUtc().year - 1;
            update(sy: year, sm: 1, ey: year, em: 12);
          },
          child: const Text('Use last complete year (12 months)'),
        ),
        Row(
          children: [
            month('Start month', w.startMonth, (m) => update(sm: m)),
            const SizedBox(width: 12),
            year('Start year', w.startYear, (y) => update(sy: y)),
          ],
        ),
        Row(
          children: [
            month('End month', w.endMonth, (m) => update(em: m)),
            const SizedBox(width: 12),
            year('End year', w.endYear, (y) => update(ey: y)),
          ],
        ),
        const Text(
          'Crop suitability remains unknown. Farmer answers are retained; previous crops, planting month and priorities are not used in climate calculations.',
        ),
      ],
    );
  }
}
