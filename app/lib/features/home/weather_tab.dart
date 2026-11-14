import 'package:flutter/cupertino.dart';

import '../../app/strings.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/feedback.dart';
import '../../design/components/grouped.dart';
import '../../design/components/page.dart';
import '../../design/components/pressable.dart';
import '../../design/components/scenario.dart' show monthNames, monthShort;
import '../../design/components/status.dart';
import '../../design/tokens.dart';
import '../results/climate_provenance.dart';

/// How a month compares with the other months of this record.
enum MonthRain { most, middle, least, unknown }

/// Splits the engine's months into thirds by rain (most / middle / least).
/// Only ranks the engine's own numbers — no rain thresholds are invented.
List<MonthRain> rankRain(List<MonthlyClimate> months) {
  final known = [for (final m in months) ?m.rainMm]..sort();
  if (known.length < 3) {
    return [
      for (final m in months)
        m.rainMm == null ? MonthRain.unknown : MonthRain.middle,
    ];
  }
  final third = known.length ~/ 3;
  final low = known[third - 1];
  final high = known[known.length - third];
  return [
    for (final m in months)
      switch (m.rainMm) {
        null => MonthRain.unknown,
        final r when r >= high => MonthRain.most,
        final r when r <= low => MonthRain.least,
        _ => MonthRain.middle,
      },
  ];
}

/// "Jun – Oct, Dec" for the months (in record order) that match.
String monthRuns(List<MonthlyClimate> months, List<bool> match) {
  final runs = <String>[];
  var i = 0;
  while (i < months.length) {
    if (!match[i]) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < months.length && match[j + 1]) {
      j++;
    }
    final a = monthShort[months[i].month - 1];
    final b = monthShort[months[j].month - 1];
    runs.add(i == j ? a : '$a – $b');
    i = j + 1;
  }
  return runs.join(', ');
}

/// Weather tab: a picture strip of the months, then 3 plain sentences.
/// Numbers appear only when the farmer taps a month.
class WeatherTab extends StatefulWidget {
  const WeatherTab({super.key, required this.analysis});
  final FieldAnalysis analysis;

  @override
  State<WeatherTab> createState() => _WeatherTabState();
}

class _WeatherTabState extends State<WeatherTab> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis;
    final c = a.climateSummary;
    final p = context.fs;
    final t = context.type;
    final months = c.months;
    final ranks = rankRain(months);
    final ref = a.reference(c.sourceId);

    MonthlyClimate? hottest;
    for (final m in months) {
      if (m.tempMeanC != null &&
          (hottest == null || m.tempMeanC! > hottest.tempMeanC!)) {
        hottest = m;
      }
    }
    final wet = monthRuns(months, [for (final r in ranks) r == MonthRain.most]);
    final dry = monthRuns(months, [
      for (final r in ranks) r == MonthRain.least,
    ]);
    final sel = _selected != null && _selected! < months.length
        ? months[_selected!]
        : null;

    return FsPage(
      title: S.tabWeather,
      showBack: false,
      subtitle: c.period.isEmpty ? null : c.period,
      children: [
        if (c.dataKind != null && c.dataKind != 'observed') ...[
          const SizedBox(height: FsSpace.md),
          FsBanner(
            message: S.notMeasured(c.dataKind!),
            tone: FsTone.caution,
            icon: CupertinoIcons.exclamationmark_circle_fill,
          ),
        ],
        if (months.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FsSpace.gutter,
              FsSpace.lg,
              FsSpace.gutter,
              0,
            ),
            child: LayoutBuilder(
              builder: (_, box) {
                const cols = 6;
                final w = ((box.maxWidth - FsSpace.xs * (cols - 1)) / cols)
                    .clamp(0.0, double.infinity);
                return Wrap(
                  spacing: FsSpace.xs,
                  runSpacing: FsSpace.xs,
                  children: [
                    for (final (i, m) in months.indexed)
                      SizedBox(
                        width: w,
                        child: _MonthCell(
                          month: m,
                          rank: ranks[i],
                          hottest: identical(m, hottest),
                          selected: i == _selected,
                          onTap: () => setState(
                            () => _selected = i == _selected ? null : i,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FsSpace.gutter,
            FsSpace.md,
            FsSpace.gutter,
            0,
          ),
          child: Semantics(
            liveRegion: true,
            child: AnimatedContainer(
              duration: FsMotion.of(context, FsMotion.fast),
              padding: const EdgeInsets.all(FsSpace.lg),
              decoration: BoxDecoration(
                color: sel == null ? p.fill : p.surface,
                borderRadius: BorderRadius.circular(FsRadius.lg),
              ),
              child: sel == null
                  ? Text(
                      S.tapMonth,
                      textAlign: TextAlign.center,
                      style: t.subhead,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${monthNames[sel.month - 1]}${sel.year == null ? '' : ' ${sel.year}'}',
                          style: t.title3,
                        ),
                        const SizedBox(height: FsSpace.xs),
                        if (sel.rainMm == null && sel.tempMeanC == null)
                          Text(S.noDataMonth, style: t.body)
                        else
                          Text(
                            [
                              '🌧️ ${sel.rainMm == null ? S.noData : '${sel.rainMm!.round()} mm ${S.rain.toLowerCase()}'}',
                              '🌡️ ${sel.tempMeanC == null ? S.noData : '${sel.tempMeanC!.toStringAsFixed(0)} °C'}',
                            ].join('    '),
                            style: t.body,
                          ),
                      ],
                    ),
            ),
          ),
        ),
        FsGroupedSection(
          separatorIndent: FsSpace.lg + 30 + FsSpace.md,
          children: [
            if (wet.isNotEmpty)
              FsListRow(
                leading: const _Emoji('🌧️'),
                title: S.mostRain,
                value: wet,
                titleStyle: t.headline,
                chevron: false,
              ),
            if (dry.isNotEmpty)
              FsListRow(
                leading: const _Emoji('☀️'),
                title: S.leastRain,
                value: dry,
                titleStyle: t.headline,
                chevron: false,
              ),
            if (hottest != null)
              FsListRow(
                leading: const _Emoji('🌡️'),
                title: S.hottest,
                value:
                    '${monthShort[hottest.month - 1]} · ${hottest.tempMeanC!.toStringAsFixed(0)} °C',
                titleStyle: t.headline,
                chevron: false,
              ),
          ],
        ),
        if (a.alerts.isNotEmpty)
          FsGroupedSection(
            header: S.watchOut,
            separatorIndent: FsSpace.lg + 26 + FsSpace.md,
            children: [
              for (final al in a.alerts)
                FsListRow(
                  leading: Icon(
                    hazardIcon(al.hazard),
                    color: p.tone(riskTone(al.level)).$1,
                    size: 26,
                  ),
                  title: hazardLabel(al.hazard),
                  titleStyle: t.headline,
                  subtitle: al.message,
                  below: FsRiskLabel(hazard: al.hazard, level: al.level),
                ),
            ],
          ),
        ClimateProvenance(analysis: a),
        if (ref != null)
          FsGroupedSection(
            header: S.whereFrom,
            separatorIndent: FsSpace.lg + 22 + FsSpace.md,
            children: [FsEvidenceRow(ref)],
          ),
      ],
    );
  }
}

class _Emoji extends StatelessWidget {
  const _Emoji(this.e);
  final String e;

  @override
  Widget build(BuildContext context) =>
      Text(e, style: const TextStyle(fontSize: 26));
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.month,
    required this.rank,
    required this.hottest,
    required this.selected,
    required this.onTap,
  });

  final MonthlyClimate month;
  final MonthRain rank;
  final bool hottest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final (emoji, word) = switch (rank) {
      MonthRain.most => ('🌧️', S.mostRain),
      MonthRain.middle => ('⛅', 'Some rain'),
      MonthRain.least => ('☀️', S.leastRain),
      MonthRain.unknown => ('❔', S.noData),
    };
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${monthNames[month.month - 1]}: $word${hottest ? ', ${S.hottest}' : ''}',
      excludeSemantics: true,
      child: FsPressable(
        onTap: onTap,
        scale: 0.94,
        child: AnimatedContainer(
          duration: FsMotion.of(context, FsMotion.fast),
          padding: const EdgeInsets.symmetric(vertical: FsSpace.sm),
          decoration: BoxDecoration(
            color: selected ? p.tintSoft : p.surface,
            borderRadius: BorderRadius.circular(FsRadius.md),
            border: Border.all(
              color: selected ? p.tint : (hottest ? p.heat : p.separator),
              width: selected || hottest ? 2 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: FsSpace.xxs),
              Text(
                monthShort[month.month - 1],
                style: context.type.footnote.copyWith(
                  color: selected ? p.tint : p.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
