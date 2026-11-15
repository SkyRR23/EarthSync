import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/environment/forecast.dart';
import '../../data/environment/recent_conditions.dart';
import '../../design/components/buttons.dart';
import '../../design/components/earth.dart';
import '../../design/components/page.dart' show FsBackArrow;
import '../../design/tokens.dart';
import '../../state/providers.dart';
import '../../state/today.dart';
import '../today/farm_tasks.dart' show shortDate;
import 'home_shell.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// One factual line about today's rain from the forecast (no advice).
String rainTip(ForecastDay? today) {
  if (today == null) return S.forecastLoading;
  final mm = today.rainMm, chance = today.rainChance;
  if ((mm ?? 0) >= 1) return S.rainToday(mm!.round());
  if (chance != null && chance >= 30) return S.rainChanceToday(chance);
  return S.noRainToday;
}

/// Weather tab (team design): forecast now and 5 days (Open-Meteo), then
/// NASA's last 7 days and the past year at the farm.
class WeatherTab extends ConsumerStatefulWidget {
  const WeatherTab({super.key});

  @override
  ConsumerState<WeatherTab> createState() => _WeatherTabState();
}

class _WeatherTabState extends ConsumerState<WeatherTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(forecastProvider.notifier).ensureFresh();
      ref.read(recentProvider.notifier).ensureFresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(farmerDraftProvider);
    if (!d.hasLocation) return const NoFarmView();
    final p = context.fs;
    final t = context.type;
    final fc = ref.watch(forecastProvider);
    final f = fc.data;
    final recent = ref.watch(recentProvider).data;
    final tabs = HomeTabs.of(context);
    final today = f == null || f.days.isEmpty ? null : f.days.first;
    final tomorrow = f == null || f.days.length < 2 ? null : f.days[1];

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FsSpace.maxContent),
            child: RefreshIndicator(
              color: p.tint,
              onRefresh: () async {
                await Future.wait([
                  ref.read(forecastProvider.notifier).refresh(),
                  ref.read(recentProvider.notifier).refresh(),
                ]);
              },
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: FsSpace.xxxl + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FsSpace.xs,
                      FsSpace.sm,
                      FsSpace.gutter,
                      0,
                    ),
                    child: Row(
                      children: [
                        FsBackArrow(onTap: () => tabs?.go(0)),
                        const SizedBox(width: FsSpace.xs),
                        Expanded(
                          child: Text(
                            S.weatherTitle,
                            style: t.title1.copyWith(fontSize: 26),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: FsSpace.sm),
                    child: Center(
                      child: FsLocationChip(
                        label: S.myFarm,
                        onTap: () => tabs?.go(2),
                      ),
                    ),
                  ),
                  FsEntrance(
                    child: _NowCard(forecast: f, tip: rainTip(today)),
                  ),
                  if (fc.loading && f == null ||
                      fc.failed && f == null ||
                      fc.failed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        FsSpace.gutter + FsSpace.xxs,
                        FsSpace.sm,
                        FsSpace.gutter,
                        0,
                      ),
                      child: Text(
                        fc.loading
                            ? S.forecastLoading
                            : f != null
                            ? S.forecastOld(_hm(f.fetchedAt))
                            : S.forecastFailed,
                        style: t.subhead.copyWith(color: p.secondaryLabel),
                      ),
                    ),
                  const FsSectionTitle(S.forecast5),
                  if (f != null && f.days.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        FsSpace.gutter - 3,
                        FsSpace.sm,
                        FsSpace.gutter - 3,
                        0,
                      ),
                      child: Row(
                        children: [
                          for (final (i, day) in f.days.take(5).indexed)
                            Expanded(
                              child: FsEntrance(
                                index: i + 1,
                                child: _DayCard(day: day, isToday: i == 0),
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    const _Placeholder(height: 120),
                  if (tomorrow != null && (tomorrow.rainMm ?? 0) >= 1)
                    FsEntrance(
                      index: 3,
                      child: FsCard(
                        color: p.cautionBg,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              CupertinoIcons.exclamationmark_triangle_fill,
                              color: p.cautionText,
                              size: 30,
                            ),
                            const SizedBox(width: FsSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    S.rainTomorrow,
                                    style: t.headline.copyWith(
                                      color: p.cautionText,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: FsSpace.xxs),
                                  Text(
                                    S.rainTomorrowBody(
                                      tomorrow.rainMm!.round(),
                                      tomorrow.rainChance,
                                    ),
                                    style: t.callout,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (f != null)
                    FsEntrance(
                      index: 4,
                      child: FsCard(
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: _Metric(
                                  icon: CupertinoIcons.drop_fill,
                                  color: p.rain,
                                  label: S.rainfall,
                                  value: today?.rainMm == null
                                      ? S.unknown
                                      : S.aboutMm(today!.rainMm!),
                                ),
                              ),
                              VerticalDivider(
                                color: p.separator,
                                width: FsSpace.xl,
                              ),
                              Expanded(
                                child: _Metric(
                                  icon: CupertinoIcons.wind,
                                  color: p.rain,
                                  label: S.wind,
                                  value: f.current.windKmh == null
                                      ? S.unknown
                                      : S.kmh(f.current.windKmh!),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FsSpace.gutter,
                      FsSpace.md,
                      FsSpace.gutter,
                      0,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FsSpace.md,
                        vertical: FsSpace.sm,
                      ),
                      decoration: BoxDecoration(
                        color: p.neutralBg,
                        borderRadius: BorderRadius.circular(FsRadius.capsule),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.info_circle,
                            size: 18,
                            color: p.secondaryLabel,
                          ),
                          const SizedBox(width: FsSpace.sm),
                          Expanded(
                            child: Text(
                              S.forecastNote,
                              style: t.footnote.copyWith(color: p.neutralText),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const FsSectionTitle(S.nasaLast7),
                  FsEntrance(index: 5, child: _NasaRecentCard(recent: recent)),
                  const FsSectionTitle(S.nasaPastYear),
                  FsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(S.pastYearBody, style: t.callout),
                        const SizedBox(height: FsSpace.md),
                        FsButton(
                          S.seeMonths,
                          kind: FsButtonKind.tinted,
                          icon: CupertinoIcons.calendar,
                          onPressed: () => context.push('/climate'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// The sky card: picture, temperature, words, "feels like", and a tip strip.
class _NowCard extends StatelessWidget {
  const _NowCard({required this.forecast, required this.tip});
  final Forecast? forecast;
  final String tip;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final c = forecast?.current;
    final (label, emoji) = weatherLook(c?.code);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FsSpace.gutter,
        FsSpace.lg,
        FsSpace.gutter,
        0,
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.sky, p.skySoft],
          ),
          borderRadius: BorderRadius.circular(FsRadius.xl),
          boxShadow: FsShadow.card(p),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FsSpace.lg,
                FsSpace.xl,
                FsSpace.xl,
                FsSpace.lg,
              ),
              child: Row(
                children: [
                  _Floating(
                    child: Text(emoji, style: const TextStyle(fontSize: 84)),
                  ),
                  const SizedBox(width: FsSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          c?.tempC == null ? '—' : '${c!.tempC!.round()}°',
                          style: t.largeTitle.copyWith(
                            fontSize: 64,
                            height: 1,
                            letterSpacing: -2,
                          ),
                        ),
                        const SizedBox(height: FsSpace.xs),
                        Text(
                          c == null ? S.forecastLoading : label,
                          textAlign: TextAlign.end,
                          style: t.title2.copyWith(fontSize: 21),
                        ),
                        if (c?.feelsLikeC != null)
                          Text(
                            S.feelsLike(c!.feelsLikeC!.round()),
                            style: t.body.copyWith(color: p.secondaryLabel),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: p.tintSoft.withValues(alpha: 0.9),
              padding: const EdgeInsets.symmetric(
                horizontal: FsSpace.lg,
                vertical: FsSpace.md,
              ),
              child: Row(
                children: [
                  Icon(Icons.eco_rounded, color: p.positiveText, size: 22),
                  const SizedBox(width: FsSpace.sm),
                  Expanded(
                    child: Text(
                      tip,
                      style: t.callout.copyWith(
                        color: p.positiveText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gently bobbing picture (still when the phone asks for less motion).
class _Floating extends StatefulWidget {
  const _Floating({required this.child});
  final Widget child;

  @override
  State<_Floating> createState() => _FloatingState();
}

class _FloatingState extends State<_Floating>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion || !TickerMode.valuesOf(context).enabled) {
      _c.stop();
    } else if (!_c.isAnimating && TickerMode.valuesOf(context).enabled) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (_, child) => Transform.translate(
      offset: Offset(0, -4 + 8 * Curves.easeInOut.transform(_c.value)),
      child: child,
    ),
  );
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.isToday});
  final ForecastDay day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final (_, emoji) = weatherLook(day.code);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: FsSpace.md),
      decoration: BoxDecoration(
        color: isToday ? p.tintSoft : p.surface,
        borderRadius: BorderRadius.circular(FsRadius.lg),
        boxShadow: FsShadow.soft(p),
      ),
      child: Column(
        children: [
          Text(
            isToday ? S.todayShort : _weekdays[day.date.weekday - 1],
            style: t.subhead.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: FsSpace.xs),
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(height: FsSpace.xs),
          Text(
            day.maxC == null ? '—' : '${day.maxC!.round()}°',
            style: t.headline.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            day.minC == null ? '—' : '${day.minC!.round()}°',
            style: t.subhead.copyWith(color: p.secondaryLabel),
          ),
          if (day.rainChance != null) ...[
            const SizedBox(height: FsSpace.xxs),
            Text(
              '💧${day.rainChance}%',
              style: t.caption.copyWith(color: p.rain),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Row(
      children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(width: FsSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: t.subhead.copyWith(color: context.fs.secondaryLabel),
              ),
              Text(
                value,
                style: t.title3.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// NASA POWER's last 7 days at the farm (a few days behind today).
class _NasaRecentCard extends StatelessWidget {
  const _NasaRecentCard({required this.recent});
  final RecentConditions? recent;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final r = recent;
    if (r == null || r.asOf == null) {
      return FsCard(child: Text(S.nasaNotYet, style: t.callout));
    }
    final compared = switch (r.rainVsPast) {
      Compared.lower => S.lessThanUsual,
      Compared.higher => S.moreThanUsual,
      Compared.usual => S.aboutUsual,
      Compared.unknown => null,
    };
    final wet = switch (r.wetnessVsPast) {
      Compared.lower => S.wetnessDrier,
      Compared.higher => S.wetnessWetter,
      Compared.usual => S.wetnessUsual,
      Compared.unknown => null,
    };
    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                r.rain7dMm == null ? '—' : '${r.rain7dMm!.round()} mm',
                style: t.title1.copyWith(color: p.rain),
              ),
              const SizedBox(width: FsSpace.sm),
              Expanded(
                child: Text(
                  S.rainfall,
                  style: t.subhead.copyWith(color: p.secondaryLabel),
                ),
              ),
            ],
          ),
          if (compared != null) Text(compared, style: t.callout),
          if (wet != null)
            Padding(
              padding: const EdgeInsets.only(top: FsSpace.xs),
              child: Text(wet, style: t.callout),
            ),
          const SizedBox(height: FsSpace.sm),
          Text(S.nasaRecentSource(shortDate(r.asOf!)), style: t.footnote),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FsSpace.gutter,
      FsSpace.sm,
      FsSpace.gutter,
      0,
    ),
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: context.fs.fill,
        borderRadius: BorderRadius.circular(FsRadius.lg),
      ),
    ),
  );
}
