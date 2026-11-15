import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/models/farmer_input.dart';
import '../../design/components/buttons.dart';
import '../../design/components/earth.dart';
import '../../design/components/page.dart' show FsBackArrow;
import '../../design/components/pressable.dart';
import '../../design/components/scenario.dart' show cropEmoji, monthNames;
import '../../design/tokens.dart';
import '../../state/account.dart';
import '../../state/providers.dart';
import '../../state/today.dart';
import '../location/gps.dart';

/// New-user setup in the team design (15 Nov): welcome, then 7 steps.
/// 1 location · 2 farm · 3 crops · 4 water (EarthSync's own question, in the
/// same style) · 5 season · 6 alerts · 7 sign in or register.
const kSetupSteps = 7;

const _img = 'assets/onboarding';

/// Welcome: farmer picture over a sky, then "Let's set up your farm!".
class SetupWelcome extends StatelessWidget {
  const SetupWelcome({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.surface,
      body: Column(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.sky, p.surface],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    const SizedBox(height: FsSpace.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.eco_rounded, color: p.tint, size: 34),
                        const SizedBox(width: FsSpace.sm),
                        Text(
                          S.appName,
                          style: t.title2.copyWith(color: p.heading),
                        ),
                      ],
                    ),
                    Text(
                      S.tagline,
                      style: t.subhead.copyWith(color: p.secondaryLabel),
                    ),
                    Expanded(
                      child: FsEntrance(
                        child: Padding(
                          padding: const EdgeInsets.all(FsSpace.lg),
                          child: Image.asset(
                            '$_img/farmer.png',
                            fit: BoxFit.contain,
                            semanticLabel:
                                'A farmer in a rice field with a phone',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          FsEntrance(
            index: 1,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                FsSpace.xxl,
                FsSpace.xl,
                FsSpace.xxl,
                FsSpace.lg + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(FsRadius.sheet + 8),
                ),
                boxShadow: FsShadow.card(p),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: FsSpace.maxContent),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      S.setupTitle,
                      textAlign: TextAlign.center,
                      style: t.title1,
                    ),
                    const SizedBox(height: FsSpace.sm),
                    Text(
                      S.setupBody,
                      textAlign: TextAlign.center,
                      style: t.body.copyWith(color: p.secondaryLabel),
                    ),
                    const SizedBox(height: FsSpace.lg),
                    const _Dots(count: 4, active: 0),
                    const SizedBox(height: FsSpace.lg),
                    FsButton(
                      S.getStartedSetup,
                      icon: CupertinoIcons.arrow_right,
                      iconAfter: true,
                      onPressed: () => context.push('/setup/1'),
                    ),
                    CupertinoButton(
                      onPressed: () => context.push('/signin'),
                      child: Text(
                        S.haveAccount,
                        style: t.subhead.copyWith(color: p.tint),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});
  final int count, active;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: FsMotion.of(context, FsMotion.normal),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 18 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active ? p.tint : p.fillStrong,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

/// One setup step: back arrow, progress "n / 7", picture, title, content,
/// and the green button at the bottom.
class SetupStepFrame extends StatelessWidget {
  const SetupStepFrame({
    super.key,
    required this.step,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.primary,
    this.image,
    this.picture,
    this.secondary,
  });
  final int step;
  final String title, subtitle;
  final String? image;
  final Widget? picture;
  final List<Widget> children;
  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FsSpace.maxContent),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.xs,
                    FsSpace.xs,
                    FsSpace.gutter,
                    0,
                  ),
                  child: Row(
                    children: [
                      FsBackArrow(
                        onTap: () => context.canPop()
                            ? context.pop()
                            : context.go(step > 1 ? '/setup/${step - 1}' : '/'),
                      ),
                      const SizedBox(width: FsSpace.sm),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: (step - 1) / kSetupSteps,
                              end: step / kSetupSteps,
                            ),
                            duration: FsMotion.of(context, FsMotion.slow),
                            curve: FsMotion.curve,
                            builder: (_, v, _) => LinearProgressIndicator(
                              value: v,
                              minHeight: 8,
                              color: p.tint,
                              backgroundColor: p.fill,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: FsSpace.md),
                      Text(
                        S.stepSlash(step, kSetupSteps),
                        style: t.subhead.copyWith(color: p.secondaryLabel),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      FsSpace.xl,
                      FsSpace.sm,
                      FsSpace.xl,
                      FsSpace.lg,
                    ),
                    children: [
                      FsEntrance(
                        child: SizedBox(
                          height: 190,
                          child:
                              picture ??
                              Image.asset(
                                '$_img/$image',
                                fit: BoxFit.contain,
                                excludeFromSemantics: true,
                              ),
                        ),
                      ),
                      const SizedBox(height: FsSpace.md),
                      FsEntrance(
                        index: 1,
                        child: Column(
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                style: t.title2.copyWith(fontSize: 24),
                              ),
                            ),
                            const SizedBox(height: FsSpace.xs),
                            Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: t.body.copyWith(color: p.secondaryLabel),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                      FsEntrance(
                        index: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.xl,
                    0,
                    FsSpace.xl,
                    FsSpace.sm,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [primary, ?secondary],
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

Widget _textButton(BuildContext context, String label, VoidCallback onTap) =>
    CupertinoButton(
      onPressed: onTap,
      child: Text(
        label,
        style: context.type.subhead.copyWith(
          color: context.fs.tint,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

/// The step screens, by number (route /setup/:step).
class SetupStepScreen extends ConsumerWidget {
  const SetupStepScreen({super.key, required this.step});
  final int step;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (step) {
    1 => const _LocationStep(),
    2 => const _FarmStep(),
    3 => const _CropsStep(),
    4 => const _WaterStep(),
    5 => const _SeasonStep(),
    6 => const _AlertsStep(),
    _ => const _AccountStep(),
  };
}

void _next(BuildContext context, int step) =>
    context.push(step >= kSetupSteps ? '/home' : '/setup/${step + 1}');

// 1 · Location ----------------------------------------------------------------

class _LocationStep extends ConsumerStatefulWidget {
  const _LocationStep();

  @override
  ConsumerState<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends ConsumerState<_LocationStep> {
  bool _busy = false;
  String? _message;

  Future<void> _allow() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final r = await readGps();
    if (!mounted) return;
    setState(() => _busy = false);
    final pt = r.point;
    if (pt == null) {
      setState(() => _message = r.message ?? S.gpsFailed);
      return;
    }
    ref
        .read(farmerDraftProvider.notifier)
        .setLocation(pt.latitude, pt.longitude);
    _next(context, 1);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final has = ref.watch(farmerDraftProvider).hasLocation;
    return SetupStepFrame(
      step: 1,
      image: 'location.png',
      title: S.allowLocationTitle,
      subtitle: S.allowLocationBody,
      primary: has
          ? FsButton(
              S.next,
              icon: CupertinoIcons.arrow_right,
              iconAfter: true,
              onPressed: () => _next(context, 1),
            )
          : FsButton(
              _busy ? S.finding : S.allowLocation,
              icon: CupertinoIcons.location_solid,
              loading: _busy,
              onPressed: _busy ? null : _allow,
            ),
      secondary: _textButton(
        context,
        S.pinOnMap,
        () => context.push('/location?setup=1'),
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(FsSpace.md),
          decoration: BoxDecoration(
            color: p.tintSoft,
            borderRadius: BorderRadius.circular(FsRadius.lg),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.checkmark_shield_fill,
                color: p.positiveText,
                size: 26,
              ),
              const SizedBox(width: FsSpace.md),
              Expanded(
                child: Text(
                  S.locationPrivacy,
                  style: t.callout.copyWith(color: p.positiveText),
                ),
              ),
            ],
          ),
        ),
        if (has) ...[
          const SizedBox(height: FsSpace.md),
          const Center(child: FsStatusPill(S.locationSaved)),
        ],
        if (_message != null) ...[
          const SizedBox(height: FsSpace.md),
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: t.subhead.copyWith(color: p.cautionText),
          ),
        ],
      ],
    );
  }
}

// 2 · Farm ----------------------------------------------------------------------

class _FarmStep extends ConsumerStatefulWidget {
  const _FarmStep();

  @override
  ConsumerState<_FarmStep> createState() => _FarmStepState();
}

class _FarmStepState extends ConsumerState<_FarmStep> {
  late final _name = TextEditingController(
    text: ref.read(farmerDraftProvider).farmName ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final type = ref.watch(farmerDraftProvider).farmType ?? 'crop';
    final n = ref.read(farmerDraftProvider.notifier);
    return SetupStepFrame(
      step: 2,
      image: 'farm.png',
      title: S.addFarmTitle,
      subtitle: S.addFarmBody,
      primary: FsButton(
        S.next,
        icon: CupertinoIcons.arrow_right,
        iconAfter: true,
        onPressed: () {
          n
            ..setFarmName(_name.text)
            ..setFarmType(type);
          _next(context, 2);
        },
      ),
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: S.farmNameHint,
            prefixIcon: Icon(Icons.eco_outlined, color: p.tint),
            filled: true,
            fillColor: p.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(FsRadius.lg),
              borderSide: BorderSide(color: p.separator),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(FsRadius.lg),
              borderSide: BorderSide(color: p.separator),
            ),
          ),
        ),
        const SizedBox(height: FsSpace.lg),
        Text(S.farmTypeLabel, style: t.headline),
        const SizedBox(height: FsSpace.sm),
        Row(
          children: [
            Expanded(
              child: _Choice(
                emoji: '🌾',
                label: S.cropFarm,
                selected: type == 'crop',
                onTap: () => n.setFarmType('crop'),
              ),
            ),
            const SizedBox(width: FsSpace.md),
            Expanded(
              child: _Choice(
                emoji: '🐄',
                label: S.livestockFarm,
                selected: type == 'livestock',
                onTap: () => n.setFarmType('livestock'),
              ),
            ),
          ],
        ),
        if (type == 'livestock') ...[
          const SizedBox(height: FsSpace.md),
          Text(
            S.livestockNote,
            style: t.subhead.copyWith(color: p.cautionText),
          ),
        ],
      ],
    );
  }
}

/// Outlined pill choice (farm type, water, rain).
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.emoji,
  });
  final String label;
  final String? emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Semantics(
      button: true,
      selected: selected,
      child: FsPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: FsMotion.of(context, FsMotion.fast),
          padding: const EdgeInsets.symmetric(
            horizontal: FsSpace.md,
            vertical: FsSpace.md,
          ),
          decoration: BoxDecoration(
            color: selected ? p.tintSoft : p.surface,
            borderRadius: BorderRadius.circular(FsRadius.lg),
            border: Border.all(
              color: selected ? p.tint : p.separator,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (emoji != null) ...[
                Text(emoji!, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: FsSpace.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: context.type.subhead.copyWith(
                    color: selected ? p.tint : p.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 3 · Crops ---------------------------------------------------------------------

class _CropsStep extends ConsumerStatefulWidget {
  const _CropsStep();

  @override
  ConsumerState<_CropsStep> createState() => _CropsStepState();
}

class _CropsStepState extends ConsumerState<_CropsStep> {
  static const _main = ['rice', 'maize', 'vegetables', 'fruits'];
  static const _more = [
    'mung_bean',
    'black_gram',
    'chickpea',
    'groundnut',
    'sesame',
  ];
  late final List<String> _picked = [...ref.read(farmerDraftProvider).crops];
  late bool _showMore = _picked.any(_more.contains);

  String _label(String id) => id == 'maize' ? S.cropCorn : Crops.label(id);

  void _toggle(String id) => setState(
    () => _picked.contains(id) ? _picked.remove(id) : _picked.add(id),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final ids = [..._main, if (_showMore) ..._more];
    return SetupStepFrame(
      step: 3,
      image: 'crops.png',
      title: S.cropsTitle,
      subtitle: S.cropsBody,
      primary: FsButton(
        S.next,
        icon: CupertinoIcons.arrow_right,
        iconAfter: true,
        onPressed: () {
          ref.read(farmerDraftProvider.notifier).setCrops(_picked);
          _next(context, 3);
        },
      ),
      children: [
        LayoutBuilder(
          builder: (_, box) {
            final w = ((box.maxWidth - FsSpace.sm * 2) / 3).clamp(0.0, 200.0);
            return Wrap(
              spacing: FsSpace.sm,
              runSpacing: FsSpace.sm,
              children: [
                for (final id in ids)
                  SizedBox(
                    width: w,
                    child: _CropTile(
                      emoji: cropEmoji(id == 'fruits' ? null : id),
                      fruit: id == 'fruits',
                      label: _label(id),
                      selected: _picked.contains(id),
                      onTap: () => _toggle(id),
                    ),
                  ),
                if (!_showMore)
                  SizedBox(
                    width: w,
                    child: _CropTile(
                      emoji: '⋯',
                      label: S.cropOther,
                      selected: false,
                      onTap: () => setState(() => _showMore = true),
                    ),
                  ),
              ],
            );
          },
        ),
        if (_picked.length > 1) ...[
          const SizedBox(height: FsSpace.sm),
          Text(
            S.cropsFirstNote,
            textAlign: TextAlign.center,
            style: t.footnote,
          ),
        ],
      ],
    );
  }
}

class _CropTile extends StatelessWidget {
  const _CropTile({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
    this.fruit = false,
  });
  final String emoji, label;
  final bool selected, fruit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: FsPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: FsMotion.of(context, FsMotion.fast),
          height: 96,
          decoration: BoxDecoration(
            color: selected ? p.tintSoft : p.surface,
            borderRadius: BorderRadius.circular(FsRadius.lg),
            border: Border.all(
              color: selected ? p.tint : p.separator,
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fruit ? '🍅' : emoji,
                        style: const TextStyle(fontSize: 32),
                      ),
                      const SizedBox(height: FsSpace.xs),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.subhead.copyWith(
                          color: selected ? p.tint : p.label,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: p.tint,
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// 4 · Water (EarthSync's own question, team style) -------------------------------

class _WaterStep extends ConsumerWidget {
  const _WaterStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.fs;
    final t = context.type;
    final d = ref.watch(farmerDraftProvider);
    final n = ref.read(farmerDraftProvider.notifier);
    Widget group<T>(
      String q,
      List<(T, String)> opts,
      T? value,
      void Function(T) set,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(q, style: t.headline),
        const SizedBox(height: FsSpace.sm),
        Wrap(
          spacing: FsSpace.sm,
          runSpacing: FsSpace.sm,
          children: [
            for (final (v, label) in opts)
              _Choice(label: label, selected: value == v, onTap: () => set(v)),
          ],
        ),
      ],
    );
    return SetupStepFrame(
      step: 4,
      title: S.waterTitle,
      subtitle: S.waterBody,
      picture: Center(
        child: Container(
          width: 170,
          height: 170,
          decoration: BoxDecoration(color: p.infoBg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Text('💧🌾', style: TextStyle(fontSize: 64)),
        ),
      ),
      primary: FsButton(
        S.next,
        icon: CupertinoIcons.arrow_right,
        iconAfter: true,
        onPressed: () {
          if (d.irrigation == null) n.setIrrigation(Irrigation.unknown);
          if (d.drainage == null) n.setDrainage(Drainage.unknown);
          _next(context, 4);
        },
      ),
      children: [
        group<Irrigation>(
          S.waterQuestion,
          [
            (Irrigation.none, '🌧️ ${S.waterRain}'),
            (Irrigation.partial, '💧 ${S.waterSome}'),
            (Irrigation.full, '🚰 ${S.waterAll}'),
            (Irrigation.unknown, S.dontKnow),
          ],
          d.irrigation,
          n.setIrrigation,
        ),
        const SizedBox(height: FsSpace.lg),
        group<Drainage>(
          S.rainQuestion,
          [
            (Drainage.good, '☀️ ${S.drainFast}'),
            (Drainage.moderate, '⏳ ${S.drainDays}'),
            (Drainage.poor, '🌊 ${S.drainLong}'),
            (Drainage.unknown, S.dontKnow),
          ],
          d.drainage,
          n.setDrainage,
        ),
      ],
    );
  }
}

// 5 · Season ----------------------------------------------------------------------

class _SeasonStep extends ConsumerWidget {
  const _SeasonStep();

  Future<void> _pick(
    BuildContext context,
    String title,
    void Function(int) set,
  ) async {
    final m = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FsSpace.xl,
                0,
                FsSpace.xl,
                FsSpace.sm,
              ),
              child: Text(title, style: ctx.type.title3),
            ),
            for (var i = 1; i <= 12; i++)
              ListTile(
                title: Text(monthNames[i - 1]),
                onTap: () => Navigator.of(ctx).pop(i),
              ),
            ListTile(
              title: const Text(S.dontKnow),
              onTap: () => Navigator.of(ctx).pop(0),
            ),
          ],
        ),
      ),
    );
    if (m != null) set(m);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    final d = ref.watch(farmerDraftProvider);
    final n = ref.read(farmerDraftProvider.notifier);
    String label(int? m) => m == null
        ? S.selectMonth
        : m == 0
        ? S.dontKnow
        : monthNames[m - 1];
    Widget field(String title, int? value, void Function(int) set) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: t.headline),
        const SizedBox(height: FsSpace.sm),
        _MonthField(
          label: label(value),
          empty: value == null,
          onTap: () => _pick(context, title, set),
        ),
      ],
    );
    return SetupStepFrame(
      step: 5,
      image: 'calendar.png',
      title: S.seasonTitle,
      subtitle: S.seasonBody,
      primary: FsButton(
        S.next,
        icon: CupertinoIcons.arrow_right,
        iconAfter: true,
        onPressed: () => _next(context, 5),
      ),
      children: [
        field(S.plantingSeason, d.plantingMonth, n.setPlantingMonth),
        const SizedBox(height: FsSpace.lg),
        field(S.harvestSeason, d.harvestMonth, n.setHarvestMonth),
      ],
    );
  }
}

class _MonthField extends StatelessWidget {
  const _MonthField({
    required this.label,
    required this.empty,
    required this.onTap,
  });
  final String label;
  final bool empty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return FsPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FsSpace.md,
          vertical: FsSpace.md + 2,
        ),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(FsRadius.lg),
          border: Border.all(color: p.separator),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.calendar, color: p.secondaryLabel),
            const SizedBox(width: FsSpace.md),
            Expanded(
              child: Text(
                label,
                style: context.type.body.copyWith(
                  color: empty ? p.tertiaryLabel : p.label,
                ),
              ),
            ),
            Icon(CupertinoIcons.chevron_down, size: 18, color: p.label),
          ],
        ),
      ),
    );
  }
}

// 6 · Alerts -----------------------------------------------------------------------

class _AlertsStep extends ConsumerWidget {
  const _AlertsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.fs;
    final t = context.type;
    final a = ref.watch(alertPrefsProvider);
    final n = ref.read(alertPrefsProvider.notifier);
    Widget row(
      String emoji,
      String title,
      String sub,
      bool value,
      ValueChanged<bool> set,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: FsSpace.sm),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: FsSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.headline.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(sub, style: t.footnote),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: p.tint,
            onChanged: set,
          ),
        ],
      ),
    );
    return SetupStepFrame(
      step: 6,
      image: 'bell.png',
      title: S.alertsTitle,
      subtitle: S.alertsBody,
      primary: FsButton(
        S.finishSetup,
        icon: CupertinoIcons.checkmark_alt,
        iconAfter: true,
        onPressed: () => _next(context, 6),
      ),
      secondary: _textButton(context, S.maybeLater, () => _next(context, 6)),
      children: [
        FsCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(
            horizontal: FsSpace.lg,
            vertical: FsSpace.sm,
          ),
          child: Column(
            children: [
              row(
                '⚠️',
                S.alertWeather,
                S.alertWeatherSub,
                a.weather,
                (v) => n.set(a.copyWith(weather: v)),
              ),
              Divider(color: p.separator),
              row(
                '💧',
                S.alertWater,
                S.alertWaterSub,
                a.water,
                (v) => n.set(a.copyWith(water: v)),
              ),
              Divider(color: p.separator),
              row(
                '🌿',
                S.alertPests,
                S.alertPestsSub,
                a.pests,
                (v) => n.set(a.copyWith(pests: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: FsSpace.sm),
        Text(S.alertsNote, textAlign: TextAlign.center, style: t.footnote),
      ],
    );
  }
}

// 7 · Sign in or register -----------------------------------------------------------

class _AccountStep extends ConsumerStatefulWidget {
  const _AccountStep();

  @override
  ConsumerState<_AccountStep> createState() => _AccountStepState();
}

class _AccountStepState extends ConsumerState<_AccountStep> {
  bool _busy = false;
  String? _error;

  void _home() {
    final d = ref.read(farmerDraftProvider);
    ref.read(analysisProvider.notifier).run(d.toInput());
    context.go('/home');
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await signInAndSync(ref);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null && ref.read(authProvider)?.currentUser != null) _home();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final canSignIn = ref.watch(authProvider) != null;
    return SetupStepFrame(
      step: 7,
      image: 'farmer.png',
      title: S.accountTitle,
      subtitle: S.accountBody,
      primary: canSignIn
          ? FsButton(
              S.signInGoogle,
              icon: CupertinoIcons.person_crop_circle_fill,
              loading: _busy,
              onPressed: _busy ? null : _google,
            )
          : FsButton(S.next, onPressed: _home),
      secondary: canSignIn ? _textButton(context, S.skipForNow, _home) : null,
      children: [
        if (canSignIn)
          Text(S.accountNote, textAlign: TextAlign.center, style: t.footnote),
        if (_error != null) ...[
          const SizedBox(height: FsSpace.md),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: t.subhead.copyWith(color: p.cautionText),
          ),
        ],
      ],
    );
  }
}
