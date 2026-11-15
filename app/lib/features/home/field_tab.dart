import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/strings.dart';
import '../../data/environment/nasa_power_client.dart';
import '../../data/models/farm_boundary.dart';
import '../../data/models/farmer_input.dart';
import '../../data/models/soil_texture.dart';
import '../../data/models/field_analysis.dart';
import '../../design/components/buttons.dart';
import '../../design/components/grouped.dart';
import '../../design/components/page.dart';
import '../../design/components/pressable.dart';
import '../../design/components/scenario.dart';
import '../../design/components/sheet.dart';
import '../../design/components/status.dart';
import '../../design/tokens.dart';
import '../../state/account.dart';
import '../../state/providers.dart';
import '../map/gibs_layer.dart';
import 'weather_months_picker.dart';

/// "rain_mm.Jul 2026" -> "Rain, Jul 2026"; "drainage" -> "After rain".
String dataGapLabel(String field) {
  const names = {
    'rain_mm': 'Rain',
    'temp_mean_c': 'Heat',
    'drainage': S.drainage,
    'irrigation': S.water,
    'current_crop': S.growNow,
    'planting_month': 'Planting month',
    'soil': 'Soil',
  };
  return field.split('.').map((p) => names[p] ?? humanize(p)).join(', ');
}

void showAboutResults(BuildContext context, FieldAnalysis a) {
  const indent = FsSpace.lg + 22 + FsSpace.md;
  showFsSheet<void>(
    context,
    title: S.aboutResults,
    builder: (ctx) {
      final p = ctx.fs;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FsGroupedSection(
            children: [
              FsListRow(
                leading: Icon(CupertinoIcons.scope, color: p.tint, size: 22),
                title: S.farmNote,
                titleStyle: ctx.type.callout,
                titleMaxLines: 6,
              ),
              FsListRow(
                leading: Icon(
                  CupertinoIcons.book_fill,
                  color: p.tint,
                  size: 22,
                ),
                title: S.sources,
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/sources');
                },
              ),
            ],
          ),
          if (a.notices.isNotEmpty)
            FsGroupedSection(
              header: S.notices,
              separatorIndent: indent,
              children: [
                for (final n in a.notices)
                  FsListRow(
                    leading: Icon(
                      CupertinoIcons.info_circle_fill,
                      color: p.infoText,
                      size: 22,
                    ),
                    title: n,
                    titleStyle: ctx.type.callout,
                  ),
              ],
            ),
          if (a.dataGaps.isNotEmpty)
            FsGroupedSection(
              header: S.dataGaps,
              separatorIndent: indent,
              children: [
                for (final g in a.dataGaps)
                  FsListRow(
                    leading: Icon(
                      CupertinoIcons.question_circle,
                      color: p.secondaryLabel,
                      size: 22,
                    ),
                    title: dataGapLabel(g.field),
                    subtitle: g.reason,
                  ),
              ],
            ),
          if (a.assumptions.isNotEmpty)
            FsGroupedSection(
              header: S.assumptions,
              separatorIndent: indent,
              children: [
                for (final s in a.assumptions)
                  FsListRow(
                    leading: Icon(
                      CupertinoIcons.text_quote,
                      color: p.secondaryLabel,
                      size: 22,
                    ),
                    title: s,
                    titleStyle: ctx.type.callout,
                  ),
              ],
            ),
        ],
      );
    },
  );
}

String answerCrop(String? crop) => (crop == null || crop == kUnknown)
    ? S.dontKnow
    : '${cropEmoji(crop)} ${Crops.label(crop)}';

String answerWater(Irrigation? i) => switch (i) {
  Irrigation.full => '🚰 ${S.waterAll}',
  Irrigation.partial => '💧 ${S.waterSome}',
  Irrigation.none => '🌧️ ${S.waterRain}',
  _ => S.dontKnow,
};

String answerDrain(Drainage? d) => switch (d) {
  Drainage.poor => '🌊 ${S.drainLong}',
  Drainage.moderate => '⏳ ${S.drainDays}',
  Drainage.good => '☀️ ${S.drainFast}',
  _ => S.dontKnow,
};

String answerSoil(FarmerDraft d) {
  final texture = d.soilTexture;
  if (texture == null) return S.soilNotChecked;
  final c = soilClassFromName(texture);
  if (c == null) return S.dontKnow;
  return '${c.emoji} ${c.label}${d.soilSource == 'ai_estimate' ? ' · ${S.aiShort}' : ''}';
}

/// "2025" for a whole year, "Mar – Sep 2025", or "Nov 2024 – Feb 2025".
String windowLabel(HistoricalWindow w) {
  String m(int i) => monthShort[i - 1];
  if (w.startYear == w.endYear) {
    if (w.startMonth == 1 && w.endMonth == 12) return '${w.startYear}';
    if (w.startMonth == w.endMonth) return '${m(w.startMonth)} ${w.startYear}';
    return '${m(w.startMonth)} – ${m(w.endMonth)} ${w.startYear}';
  }
  return '${m(w.startMonth)} ${w.startYear} – ${m(w.endMonth)} ${w.endYear}';
}

/// Plain-text summary the farmer can send to an extension officer (OpenFarm
/// "share" idea, without accounts or links).
String shareSummary(FarmerDraft d, FieldAnalysis a) {
  final b = StringBuffer()
    ..writeln('${S.appName} — ${S.myFarm}')
    ..writeln(
      '${S.location}: ${d.fieldLatitude?.toStringAsFixed(5)}, ${d.fieldLongitude?.toStringAsFixed(5)}',
    );
  if (d.hasFarm) b.writeln('${S.farmSize}: ${farmSizeLabel(d.farm!)}');
  b
    ..writeln('${S.growNow}: ${answerCrop(d.currentCrop)}')
    ..writeln('${S.water}: ${answerWater(d.irrigation)}')
    ..writeln('${S.drainage}: ${answerDrain(d.drainage)}')
    ..writeln('${S.soil}: ${answerSoil(d)}')
    ..writeln();
  for (final (s, label, _) in sortedByFit(a.scenarios)) {
    final (fit, _, _) = feasibilityStyle(s.eligibility);
    b.writeln('${cropNames(s)} — $fit${s.isBaseline ? ' ($label)' : ''}');
  }
  b.writeln();
  if (a.dataQuality.isDemo) b.writeln(S.demoData);
  b.writeln(S.welcomeDisclaimer);
  return b.toString();
}

/// Field tab: the farm on a map, mark its 4 corners, answers and extras.
class FieldTab extends ConsumerStatefulWidget {
  const FieldTab({super.key});

  @override
  ConsumerState<FieldTab> createState() => _FieldTabState();
}

class _FieldTabState extends ConsumerState<FieldTab> {
  bool _plantHealth = false;

  /// The team's NASA history window (completed months, up to 24).
  Future<void> _pickWeatherMonths(BuildContext context) async {
    final before = ref.read(historicalWindowProvider);
    await showFsSheet<void>(
      context,
      title: S.weatherMonths,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(FsSpace.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FsButton(
              S.last12,
              kind: FsButtonKind.tinted,
              icon: CupertinoIcons.calendar,
              onPressed: () {
                ref
                    .read(historicalWindowProvider.notifier)
                    .setWindow(lastFullYear());
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: FsSpace.lg),
            const WeatherMonthsPicker(),
            const SizedBox(height: FsSpace.lg),
            FsButton(S.done, onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
    final after = ref.read(historicalWindowProvider);
    if (!identical(before, after) && mounted) {
      ref
          .read(analysisProvider.notifier)
          .run(ref.read(farmerDraftProvider).toInput());
    }
  }

  Future<void> _startOver() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text(S.startOver),
        content: const Text(S.startOverConfirm),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(S.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.startOver),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(farmerDraftProvider.notifier).reset();
      ref.read(analysisProvider.notifier).forget();
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(farmerDraftProvider);
    final state = ref.watch(analysisProvider);
    final a = state is AnalysisReady ? state.analysis : null;
    final user = ref.watch(userProvider).value;
    final p = context.fs;
    const iconIndent = FsSpace.lg + 30 + FsSpace.md;

    return FsPage(
      title: S.myFarm,
      showBack: false,
      subtitle: d.hasFarm ? farmSizeLabel(d.farm!) : null,
      children: [
        FarmMapCard(draft: d, plantHealth: _plantHealth),
        FsGroupedSection(
          footer: !d.hasFarm
              ? S.markFarmForHealth
              : (_plantHealth
                    ? '${plantHealthDateLabel(ref.watch(plantHealthDateProvider(d.farm!.center)).value)}. ${S.insideFarmOnly} ${S.pixelNote}'
                    : null),
          children: [
            FsListRow(
              leading: FsIconBadge(
                CupertinoIcons.leaf_arrow_circlepath,
                color: p.positiveText,
              ),
              title: S.showPlantHealth,
              chevron: false,
              trailing: CupertinoSwitch(
                value: _plantHealth && d.hasFarm,
                activeTrackColor: p.tint,
                onChanged: d.hasFarm
                    ? (v) => setState(() => _plantHealth = v)
                    : null,
              ),
              onTap: d.hasFarm
                  ? () => setState(() => _plantHealth = !_plantHealth)
                  : null,
            ),
            if (_plantHealth && d.hasFarm)
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  FsSpace.lg,
                  0,
                  FsSpace.lg,
                  FsSpace.md,
                ),
                child: PlantHealthLegend(),
              ),
          ],
        ),
        if (!d.hasFarm)
          _MarkFarmCard(onTap: () => context.push('/farm'))
        else
          FsGroupedSection(
            separatorIndent: iconIndent,
            footer: S.farmNote,
            children: [
              FsListRow(
                leading: FsIconBadge(
                  CupertinoIcons.square_on_square,
                  color: p.tint,
                ),
                title: S.farmSize,
                value: farmSizeLabel(d.farm!),
                chevron: false,
              ),
              FsListRow(
                leading: FsIconBadge(CupertinoIcons.pencil, color: p.tint),
                title: S.editFarm,
                onTap: () => context.push('/farm'),
              ),
            ],
          ),
        if (d.soilTexture == null)
          _SoilCard(onTap: () => context.push('/soil-test')),
        FsGroupedSection(
          header: S.yourAnswers,
          separatorIndent: iconIndent,
          children: [
            FsListRow(
              leading: FsIconBadge(
                CupertinoIcons.location_solid,
                color: p.crop3,
              ),
              title: S.location,
              onTap: () => context.push('/location?edit=1'),
            ),
            FsListRow(
              leading: FsIconBadge(Icons.grass_rounded, color: p.crop1),
              title: S.growNow,
              value: answerCrop(d.currentCrop),
              onTap: () => context.push('/question/1?edit=1'),
            ),
            FsListRow(
              leading: FsIconBadge(CupertinoIcons.drop_fill, color: p.rain),
              title: S.water,
              value: answerWater(d.irrigation),
              onTap: () => context.push('/question/2?edit=1'),
            ),
            FsListRow(
              leading: FsIconBadge(
                CupertinoIcons.cloud_rain_fill,
                color: p.crop3,
              ),
              title: S.drainage,
              value: answerDrain(d.drainage),
              onTap: () => context.push('/question/3?edit=1'),
            ),
            FsListRow(
              leading: FsIconBadge(
                CupertinoIcons.hand_raised_fill,
                color: p.crop2,
              ),
              title: S.soil,
              value: answerSoil(d),
              onTap: () => context.push('/soil-test'),
            ),
          ],
        ),
        FsGroupedSection(
          separatorIndent: iconIndent,
          children: [
            FsListRow(
              leading: FsIconBadge(CupertinoIcons.calendar, color: p.rain),
              title: S.weatherMonths,
              value: windowLabel(ref.watch(historicalWindowProvider)),
              onTap: () => _pickWeatherMonths(context),
            ),
            if (a != null) ...[
              FsListRow(
                leading: FsIconBadge(CupertinoIcons.share, color: p.tint),
                title: S.share,
                onTap: () => SharePlus.instance.share(
                  ShareParams(text: shareSummary(d, a), subject: S.appName),
                ),
              ),
              FsListRow(
                leading: FsIconBadge(
                  CupertinoIcons.info,
                  color: p.secondaryLabel,
                ),
                title: S.aboutResults,
                onTap: () => showAboutResults(context, a),
              ),
            ] else
              FsListRow(
                leading: FsIconBadge(
                  CupertinoIcons.book_fill,
                  color: p.secondaryLabel,
                ),
                title: S.sources,
                onTap: () => context.push('/sources'),
              ),
          ],
        ),
        if (ref.watch(authProvider) != null)
          FsGroupedSection(
            separatorIndent: iconIndent,
            footer: user == null ? S.signInBody : null,
            children: [
              if (user == null)
                FsListRow(
                  leading: FsIconBadge(
                    CupertinoIcons.cloud_upload_fill,
                    color: p.tint,
                  ),
                  title: S.saveOnline,
                  onTap: () async {
                    final error = await signInAndSync(ref);
                    if (error != null && context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error)));
                    }
                  },
                )
              else ...[
                FsListRow(
                  leading: FsIconBadge(
                    CupertinoIcons.checkmark_seal_fill,
                    color: p.positiveText,
                  ),
                  title: S.savedOnline,
                  value: user.email ?? user.displayName ?? S.account,
                  chevron: false,
                ),
                FsListRow(
                  leading: FsIconBadge(
                    CupertinoIcons.square_arrow_right,
                    color: p.secondaryLabel,
                  ),
                  title: S.signOut,
                  onTap: () => signOut(ref),
                ),
              ],
            ],
          ),
        FsGroupedSection(
          children: [
            FsListRow(
              leading: FsIconBadge(
                CupertinoIcons.lock_shield_fill,
                color: p.secondaryLabel,
              ),
              title: S.yourData,
              onTap: () => context.push('/your-data'),
            ),
          ],
        ),
        FsGroupedSection(
          children: [
            FsListRow(
              title: S.startOver,
              titleStyle: context.type.body.copyWith(color: p.negativeText),
              chevron: false,
              onTap: _startOver,
            ),
          ],
        ),
      ],
    );
  }
}

class _MarkFarmCard extends StatelessWidget {
  const _MarkFarmCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FsSpace.gutter,
        FsSpace.xl,
        FsSpace.gutter,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(FsSpace.lg),
        decoration: BoxDecoration(
          color: p.tintSoft,
          borderRadius: BorderRadius.circular(FsRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('📍', style: TextStyle(fontSize: 30)),
                const SizedBox(width: FsSpace.md),
                Expanded(child: Text(S.markFarm, style: t.title3)),
              ],
            ),
            const SizedBox(height: FsSpace.sm),
            Text(S.markFarmBody, style: t.body),
            const SizedBox(height: FsSpace.lg),
            FsButton(
              S.markFarm,
              icon: CupertinoIcons.map_pin_ellipse,
              onPressed: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

/// Still map of the farm (outline once marked, else the pin). Tap = full map.
class FarmMapCard extends StatelessWidget {
  const FarmMapCard({
    super.key,
    required this.draft,
    required this.plantHealth,
  });
  final FarmerDraft draft;
  final bool plantHealth;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final pin = LatLng(
      draft.latitude ?? kSampleLat,
      draft.longitude ?? kSampleLon,
    );
    final farm = draft.hasFarm ? draft.farm! : null;
    final camera = farm == null
        ? null
        : CameraFit.coordinates(
            coordinates: farm.corners,
            padding: const EdgeInsets.all(48),
            maxZoom: 18,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FsSpace.gutter,
        FsSpace.lg,
        FsSpace.gutter,
        0,
      ),
      child: FsPressable(
        onTap: () => context.push('/map${plantHealth ? '?layer=health' : ''}'),
        semanticLabel: '${S.myFarm} map',
        scale: 0.98,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FsRadius.lg),
          child: SizedBox(
            height: 240,
            child: Stack(
              children: [
                IgnorePointer(
                  child: FlutterMap(
                    key: ValueKey('${farm?.center}-$plantHealth'),
                    options: MapOptions(
                      initialCenter: farm?.center ?? pin,
                      initialZoom: 15,
                      initialCameraFit: camera,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      streetTileLayer(),
                      if (plantHealth && farm != null)
                        plantHealthLayer(farmCorners: farm.corners),
                      if (farm != null)
                        farmOutlineLayer(context, farm)
                      else
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: pin,
                              width: 44,
                              height: 44,
                              child: fieldMarker(context),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Positioned(
                  right: FsSpace.sm,
                  bottom: FsSpace.sm,
                  child: Container(
                    padding: const EdgeInsets.all(FsSpace.sm),
                    decoration: BoxDecoration(
                      color: p.surfaceRaised.withValues(alpha: 0.92),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.fullscreen,
                      color: p.tint,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The farm's outline, drawn on any map.
Widget farmOutlineLayer(BuildContext context, FarmBoundary farm) {
  final p = context.fs;
  return PolygonLayer(
    polygons: [
      Polygon(
        points: farm.corners,
        color: p.tint.withValues(alpha: 0.18),
        borderColor: p.tint,
        borderStrokeWidth: 3,
      ),
    ],
  );
}

class _SoilCard extends StatelessWidget {
  const _SoilCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FsSpace.gutter,
        FsSpace.xl,
        FsSpace.gutter,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(FsSpace.lg),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(FsRadius.lg),
          border: Border.all(color: p.separator),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('🤲', style: TextStyle(fontSize: 30)),
                const SizedBox(width: FsSpace.md),
                Expanded(child: Text(S.soilTitle, style: t.title3)),
              ],
            ),
            const SizedBox(height: FsSpace.sm),
            Text(S.soilCard, style: t.body),
            const SizedBox(height: FsSpace.lg),
            FsButton(S.soilTitle, kind: FsButtonKind.tinted, onPressed: onTap),
          ],
        ),
      ),
    );
  }
}
