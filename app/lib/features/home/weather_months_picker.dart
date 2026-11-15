import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../data/environment/nasa_power_client.dart';
import '../../data/models/field_analysis.dart' show EngineError;
import '../../design/tokens.dart';
import '../../state/providers.dart';

/// The NASA window for [from]..[to], or null when the data rule refuses it
/// (unfinished months, wrong order, more than 24 months). Uses the same check
/// the NASA client runs, so the picker never applies a window that would fail.
HistoricalWindow? windowIfValid(DateTime from, DateTime to) {
  final w = HistoricalWindow(
    startYear: from.year,
    startMonth: from.month,
    endYear: to.year,
    endMonth: to.month,
  );
  try {
    w.validate();
    return w;
  } on EngineError {
    return null;
  }
}

/// Weather months: a "From" and a "To" month wheel. A choice is applied only
/// when it is allowed; otherwise the farmer is told why and nothing changes.
class WeatherMonthsPicker extends ConsumerStatefulWidget {
  const WeatherMonthsPicker({super.key});

  @override
  ConsumerState<WeatherMonthsPicker> createState() =>
      _WeatherMonthsPickerState();
}

class _WeatherMonthsPickerState extends ConsumerState<WeatherMonthsPicker> {
  static final _first = DateTime(1981, 1);
  late final DateTime _last;
  late DateTime _from, _to;
  bool _bad = false;

  DateTime _clamp(DateTime d) =>
      d.isBefore(_first) ? _first : (d.isAfter(_last) ? _last : d);

  @override
  void initState() {
    super.initState();
    final n = DateTime.now().toUtc();
    _last = DateTime(n.year, n.month - 1); // last finished month
    final w = ref.read(historicalWindowProvider);
    _from = _clamp(DateTime(w.startYear, w.startMonth));
    _to = _clamp(DateTime(w.endYear, w.endMonth));
  }

  void _changed({DateTime? from, DateTime? to}) {
    setState(() {
      _from = from ?? _from;
      _to = to ?? _to;
      final w = windowIfValid(_from, _to);
      _bad = w == null;
      if (w != null) ref.read(historicalWindowProvider.notifier).setWindow(w);
    });
  }

  Widget _wheel(String label, DateTime value, ValueChanged<DateTime> change) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.type.headline),
        SizedBox(
          height: 140,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.monthYear,
            initialDateTime: value,
            minimumDate: _first,
            maximumDate: _last,
            onDateTimeChanged: (d) => change(DateTime(d.year, d.month)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          S.weatherMonthsHelp,
          style: context.type.subhead.copyWith(color: p.secondaryLabel),
        ),
        const SizedBox(height: FsSpace.md),
        _wheel(S.weatherFrom, _from, (d) => _changed(from: d)),
        const SizedBox(height: FsSpace.md),
        _wheel(S.weatherTo, _to, (d) => _changed(to: d)),
        if (_bad) ...[
          const SizedBox(height: FsSpace.md),
          Semantics(
            liveRegion: true,
            child: Text(
              S.weatherMonthsBad,
              style: context.type.subhead.copyWith(color: p.negativeText),
            ),
          ),
        ],
      ],
    );
  }
}
