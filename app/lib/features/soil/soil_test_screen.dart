import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/strings.dart';
import '../../data/models/field_note.dart';
import '../../data/models/soil_texture.dart';
import '../../data/photos/photo_store.dart';
import '../../data/soil/soil_ai_client.dart';
import '../../design/components/buttons.dart';
import '../../design/components/page.dart';
import '../../design/components/picture_tiles.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

enum _Step {
  intro,
  photoGround,
  photoSqueeze,
  ribbon,
  feel,
  signs,
  checking,
  result,
}

String soilSignLabel(SoilSign s) => switch (s) {
  SoilSign.cracks => S.signCracks,
  SoilSign.whiteCrust => S.signWhiteCrust,
  SoilSign.greySpots => S.signGreySpots,
  SoilSign.stones => S.signStones,
  SoilSign.darkTopsoil => S.signDarkTopsoil,
  SoilSign.waterlogged => S.signWaterlogged,
  SoilSign.rootsOrWorms => S.signRootsOrWorms,
};

/// "Check your soil": 2 photos + 2 hand-test answers + what you see.
/// With photos and internet the backend asks Claude for an estimate (12 soil
/// types); otherwise — or when the AI is not sure — the hand-test key decides.
/// The result is always labelled (AI estimate / hand test), never a lab value.
class SoilTestScreen extends ConsumerStatefulWidget {
  const SoilTestScreen({super.key});

  @override
  ConsumerState<SoilTestScreen> createState() => _SoilTestScreenState();
}

class _SoilTestScreenState extends ConsumerState<SoilTestScreen> {
  _Step _step = _Step.intro;
  final _id = DateTime.now().microsecondsSinceEpoch;
  String? _ground;
  String? _squeeze;
  Ribbon? _ribbon;
  Feel? _feel;
  final Set<SoilSign> _signs = {};

  // Result
  SoilClass? _class;
  String _source = 'hand_test';
  String? _confidence;
  List<SoilSign> _aiSigns = const [];
  String? _reason;
  String? _note; // why the hand test was used instead of the AI

  SoilClass? get _hand => handKey(_ribbon, _feel);

  void _go(_Step s) => setState(() => _step = s);

  void _afterPhotos() => _go(_Step.ribbon);

  Future<void> _pick(ImageSource source, {required bool ground}) async {
    final store = ref.read(photoStoreProvider);
    if (store == null) return;
    try {
      final picked = await pickPhoto(source);
      if (picked == null) return;
      final name = await store.save(
        picked,
        'soil-$_id-${ground ? 'ground' : 'squeeze'}',
      );
      PaintingBinding.instance.imageCache.evict(FileImage(store.file(name)));
      if (!mounted) return;
      setState(() => ground ? _ground = name : _squeeze = name);
    } catch (_) {
      // No camera / permission refused: the check still works without it.
    }
  }

  Future<void> _check() async {
    _go(_Step.checking);
    final store = ref.read(photoStoreProvider);
    final photos = [
      for (final n in [_ground, _squeeze])
        if (n != null && store != null) store.file(n),
    ];
    final hand = _hand;
    SoilEstimate? ai;
    String? note;
    if (photos.isNotEmpty) {
      try {
        final d = ref.read(farmerDraftProvider);
        ai = await ref
            .read(soilAiProvider)
            .estimate(
              photos: photos,
              ribbon: _ribbon,
              feel: _feel,
              signs: _signs,
              latitude: d.fieldLatitude,
              longitude: d.fieldLongitude,
            );
      } catch (_) {
        note = S.soilAiFailed;
      }
    }
    if (!mounted) return;
    setState(() {
      if (ai != null && ai.soilClass != null) {
        _class = ai.soilClass;
        _source = 'ai_estimate';
        _confidence = ai.confidence;
        _aiSigns = ai.signs;
        _reason = ai.reason;
      } else {
        if (ai != null) note = S.soilAiUnsure;
        _class = hand;
        _source = 'hand_test';
        _confidence = hand == null ? 'low' : 'medium';
        _aiSigns = ai?.signs ?? const [];
        _reason = null;
      }
      _note = note;
      _step = _Step.result;
    });
  }

  void _save() {
    final signs = {..._signs, ..._aiSigns}.toList();
    ref
        .read(farmerDraftProvider.notifier)
        .setSoilResult(
          soilClass: _class,
          source: _source,
          confidence: _confidence,
          signs: signs,
        );
    final label = _class == null
        ? S.dontKnow
        : '${_class!.label}${_source == 'ai_estimate' ? ' (${S.aiShort})' : ''}';
    final notes = ref.read(notesProvider.notifier);
    notes.add(
      NoteKind.soil,
      S.soilNote(label),
      photo: _ground,
      id: 'soil-$_id-ground',
    );
    if (_squeeze != null) {
      notes.add(
        NoteKind.soil,
        S.squeezedSoilNote,
        photo: _squeeze,
        id: 'soil-$_id-squeeze',
      );
    }
    final d = ref.read(farmerDraftProvider);
    if (d.hasLocation) ref.read(analysisProvider.notifier).run(d.toInput());
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final p = context.fs;
    final store = ref.watch(photoStoreProvider);
    final photosAllowed = store != null;
    const steps = 6;
    final stepNo = switch (_step) {
      _Step.intro => 1,
      _Step.photoGround || _Step.photoSqueeze => 2,
      _Step.ribbon => 3,
      _Step.feel => 4,
      _Step.signs => 5,
      _Step.checking || _Step.result => 6,
    };

    Widget question(String text, [String? hint]) => Padding(
      padding: const EdgeInsets.fromLTRB(
        FsSpace.gutter + FsSpace.xs,
        FsSpace.xl,
        FsSpace.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(text, style: t.title1)),
          if (hint != null) ...[
            const SizedBox(height: FsSpace.xs),
            Text(hint, style: t.body.copyWith(color: p.secondaryLabel)),
          ],
        ],
      ),
    );

    Widget photoStep({required bool ground}) {
      final name = ground ? _ground : _squeeze;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          FsSpace.gutter,
          FsSpace.lg,
          FsSpace.gutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(FsRadius.lg),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: name != null && store != null
                    ? Image.file(store.file(name), fit: BoxFit.cover)
                    : ColoredBox(
                        color: p.surface,
                        child: Center(
                          child: Text(
                            ground ? '🟫' : '✊',
                            style: const TextStyle(fontSize: 64),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: FsSpace.md),
            Row(
              children: [
                Expanded(
                  child: FsButton(
                    name == null ? S.takePhoto : S.retakePhoto,
                    kind: FsButtonKind.tinted,
                    icon: CupertinoIcons.camera_fill,
                    onPressed: () => _pick(ImageSource.camera, ground: ground),
                  ),
                ),
                const SizedBox(width: FsSpace.sm),
                Expanded(
                  child: FsButton(
                    S.choosePhoto,
                    kind: FsButtonKind.tinted,
                    icon: CupertinoIcons.photo,
                    onPressed: () => _pick(ImageSource.gallery, ground: ground),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final List<Widget> body = switch (_step) {
      _Step.intro => [
        question(S.soilIntroTitle),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FsSpace.gutter + FsSpace.xs,
            FsSpace.lg,
            FsSpace.gutter,
            0,
          ),
          child: Column(
            children: [
              for (final (e, line) in [
                ('⛏️', S.soilIntro1),
                ('🪨', S.soilIntro2),
                ('💧', S.soilIntro3),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: FsSpace.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e, style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: FsSpace.md),
                      Expanded(child: Text(line, style: t.body)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      _Step.photoGround => [
        question(S.photoGroundTitle, S.photoGroundHint),
        photoStep(ground: true),
      ],
      _Step.photoSqueeze => [
        question(S.photoSqueezeTitle, S.photoSqueezeHint),
        photoStep(ground: false),
      ],
      _Step.ribbon => [
        question(S.qRibbon),
        FsPictureGrid<Ribbon>(
          choices: const [
            FsPicture(Ribbon.fallsApart, '💨', S.ribbonFallsApart),
            FsPicture(Ribbon.none, '⚪', S.ribbonNone),
            FsPicture(Ribbon.short, '🤏', S.ribbonShort),
            FsPicture(Ribbon.medium, '📏', S.ribbonMedium),
            FsPicture(Ribbon.long, '🎗️', S.ribbonLong),
          ],
          selected: _ribbon,
          onSelect: (v) {
            setState(() => _ribbon = v);
            // Falls apart = sand: the feel question adds nothing.
            _go(v == Ribbon.fallsApart ? _Step.signs : _Step.feel);
          },
        ),
      ],
      _Step.feel => [
        question(S.qFeel),
        FsPictureGrid<Feel>(
          choices: const [
            FsPicture(Feel.gritty, '🏖️', S.feelGritty),
            FsPicture(Feel.smooth, '🌾', S.feelSmooth),
            FsPicture(Feel.sticky, '🍯', S.feelSticky),
          ],
          columns: 3,
          selected: _feel,
          onSelect: (v) {
            setState(() => _feel = v);
            _go(_Step.signs);
          },
        ),
      ],
      _Step.signs => [
        question(S.qSigns, S.signsHint),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FsSpace.gutter,
            FsSpace.lg,
            FsSpace.gutter,
            0,
          ),
          child: LayoutBuilder(
            builder: (_, box) {
              final w = ((box.maxWidth - FsSpace.sm) / 2).clamp(
                0.0,
                double.infinity,
              );
              return Wrap(
                spacing: FsSpace.sm,
                runSpacing: FsSpace.sm,
                children: [
                  for (final s in SoilSign.values)
                    SizedBox(
                      width: w,
                      child: FsPictureTile(
                        emoji: s.emoji,
                        label: soilSignLabel(s),
                        height: 92,
                        selected: _signs.contains(s),
                        onTap: () => setState(
                          () => _signs.contains(s)
                              ? _signs.remove(s)
                              : _signs.add(s),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
      _Step.checking => [
        Padding(
          padding: const EdgeInsets.only(top: FsSpace.huge * 2),
          child: Column(
            children: [
              const CupertinoActivityIndicator(radius: 16),
              const SizedBox(height: FsSpace.lg),
              Text(S.checkingSoil, style: t.title3),
            ],
          ),
        ),
      ],
      _Step.result => [_result(context)],
    };

    return FsPage(
      title: S.soilTitle,
      largeTitle: false,
      navMiddle: S.stepOf(stepNo, steps),
      below: FsProgressLine(
        stepNo / steps,
        semanticLabel: S.stepSemantic(stepNo, steps),
      ),
      bottomBar: switch (_step) {
        _Step.intro => FsButton(
          S.start,
          onPressed: () =>
              _go(photosAllowed ? _Step.photoGround : _Step.ribbon),
        ),
        _Step.photoGround => FsButton(
          _ground == null ? S.skipPhoto : S.next,
          kind: _ground == null ? FsButtonKind.plain : FsButtonKind.filled,
          onPressed: () => _go(_Step.photoSqueeze),
        ),
        _Step.photoSqueeze => FsButton(
          _squeeze == null ? S.skipPhoto : S.next,
          kind: _squeeze == null ? FsButtonKind.plain : FsButtonKind.filled,
          onPressed: _afterPhotos,
        ),
        _Step.ribbon => FsButton(
          S.dontKnow,
          kind: FsButtonKind.plain,
          onPressed: () {
            _ribbon = null;
            _go(_Step.feel);
          },
        ),
        _Step.feel => FsButton(
          S.dontKnow,
          kind: FsButtonKind.plain,
          onPressed: () {
            _feel = null;
            _go(_Step.signs);
          },
        ),
        _Step.signs => FsButton(S.next, onPressed: _check),
        _Step.checking => null,
        _Step.result => FsButton(
          S.saveSoil,
          icon: CupertinoIcons.checkmark_alt,
          onPressed: _save,
        ),
      },
      children: body,
    );
  }

  Widget _result(BuildContext context) {
    final t = context.type;
    final p = context.fs;
    final signs = {..._signs, ..._aiSigns}.toList();
    final hand = _hand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FsSpace.gutter,
        FsSpace.xxl,
        FsSpace.gutter,
        0,
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          children: [
            Text(_class?.emoji ?? '🤔', style: const TextStyle(fontSize: 64)),
            const SizedBox(height: FsSpace.md),
            Text(S.soilResult, style: t.footnote),
            Text(
              _class?.label ?? S.dontKnow,
              style: t.largeTitle,
              textAlign: TextAlign.center,
            ),
            if (_confidence != null && _class != null) ...[
              const SizedBox(height: FsSpace.sm),
              Text(
                S.confidenceLabel(_confidence!),
                style: t.headline.copyWith(color: p.tint),
              ),
            ],
            const SizedBox(height: FsSpace.sm),
            Text(
              _class == null
                  ? S.soilUnsure
                  : (_source == 'ai_estimate' ? S.soilFromAi : S.soilFromHands),
              textAlign: TextAlign.center,
              style: t.body.copyWith(color: p.secondaryLabel),
            ),
            if (_note != null) ...[
              const SizedBox(height: FsSpace.sm),
              Text(
                _note!,
                textAlign: TextAlign.center,
                style: t.footnote.copyWith(color: p.cautionText),
              ),
            ],
            if (_reason != null && _reason!.isNotEmpty) ...[
              const SizedBox(height: FsSpace.lg),
              Text(_reason!, textAlign: TextAlign.center, style: t.body),
            ],
            if (_source == 'ai_estimate' && hand != null && hand != _class) ...[
              const SizedBox(height: FsSpace.sm),
              Text(S.handTestSaid(hand.label), style: t.footnote),
            ],
            if (signs.isNotEmpty) ...[
              const SizedBox(height: FsSpace.lg),
              Text(S.signsSeen.toUpperCase(), style: t.caption),
              const SizedBox(height: FsSpace.xs),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: FsSpace.sm,
                runSpacing: FsSpace.xs,
                children: [
                  for (final s in signs)
                    Text('${s.emoji} ${soilSignLabel(s)}', style: t.subhead),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
