import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/strings.dart';
import '../../data/models/field_note.dart';
import '../../data/models/soil_texture.dart';
import '../../data/photos/photo_store.dart';
import '../../design/components/buttons.dart';
import '../../design/components/page.dart';
import '../../design/components/picture_tiles.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

enum _Step { intro, ball, ribbon, feel, result }

/// "Check your soil": the hand texture test (ball → ribbon → feel) in big
/// picture steps. The result is farmer-reported and labelled so; it goes to
/// the engine as soil texture. An optional soil photo is saved as a note.
class SoilTestScreen extends ConsumerStatefulWidget {
  const SoilTestScreen({super.key});

  @override
  ConsumerState<SoilTestScreen> createState() => _SoilTestScreenState();
}

class _SoilTestScreenState extends ConsumerState<SoilTestScreen> {
  _Step _step = _Step.intro;
  bool? _ball;
  Ribbon? _ribbon;
  Feel? _feel;
  bool _unsure = false;
  String? _photo;
  final _photoId = 'soil-${DateTime.now().microsecondsSinceEpoch}';

  SoilTexture? get _result => _unsure
      ? null
      : soilFromFeelTest(makesBall: _ball, ribbon: _ribbon, feel: _feel);

  void _next() {
    final r = _result;
    setState(() {
      _step = switch (_step) {
        _Step.intro => _Step.ball,
        _Step.ball => _unsure || r != null ? _Step.result : _Step.ribbon,
        _Step.ribbon => _unsure || r != null ? _Step.result : _Step.feel,
        _Step.feel => _Step.result,
        _Step.result => _Step.result,
      };
    });
  }

  void _unsureNow() {
    _unsure = true;
    setState(() => _step = _Step.result);
  }

  Future<void> _takePhoto() async {
    final store = ref.read(photoStoreProvider);
    if (store == null) return;
    try {
      final picked = await pickPhoto(ImageSource.camera);
      if (picked == null) return;
      final name = await store.save(picked, _photoId);
      PaintingBinding.instance.imageCache.evict(FileImage(store.file(name)));
      if (mounted) setState(() => _photo = name);
    } catch (_) {
      // No camera / permission refused: the test works without a photo.
    }
  }

  void _save() {
    final texture = _result;
    ref.read(farmerDraftProvider.notifier).setSoil(texture);
    if (_photo != null || texture != null) {
      ref
          .read(notesProvider.notifier)
          .add(
            NoteKind.soil,
            texture == null ? '' : S.soilNote(texture.label),
            photo: _photo,
            id: _photoId,
          );
    }
    // Soil changed: check the farm again with it.
    final d = ref.read(farmerDraftProvider);
    if (d.hasLocation) ref.read(analysisProvider.notifier).run(d.toInput());
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final p = context.fs;
    final store = ref.watch(photoStoreProvider);
    const steps = 4;
    final stepNo = switch (_step) {
      _Step.intro => 1,
      _Step.ball => 2,
      _Step.ribbon || _Step.feel => 3,
      _Step.result => 4,
    };

    Widget question(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        FsSpace.gutter + FsSpace.xs,
        FsSpace.xl,
        FsSpace.gutter,
        0,
      ),
      child: Semantics(header: true, child: Text(text, style: t.title1)),
    );

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
            crossAxisAlignment: CrossAxisAlignment.start,
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
              if (store != null) ...[
                const SizedBox(height: FsSpace.sm),
                if (_photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(FsRadius.md),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.file(store.file(_photo!), fit: BoxFit.cover),
                    ),
                  )
                else
                  Text(S.soilPhotoHint, style: t.footnote),
                const SizedBox(height: FsSpace.sm),
                FsButton(
                  S.takePhoto,
                  kind: FsButtonKind.tinted,
                  icon: CupertinoIcons.camera_fill,
                  onPressed: _takePhoto,
                ),
              ],
            ],
          ),
        ),
      ],
      _Step.ball => [
        question(S.qBall),
        FsPictureGrid<bool>(
          choices: const [
            FsPicture(true, '⚪', S.ballYes),
            FsPicture(false, '💨', S.ballNo),
          ],
          selected: _ball,
          onSelect: (v) {
            setState(() => _ball = v);
            _next();
          },
        ),
      ],
      _Step.ribbon => [
        question(S.qRibbon),
        FsPictureGrid<Ribbon>(
          choices: const [
            FsPicture(Ribbon.none, '✋', S.ribbonNone),
            FsPicture(Ribbon.short, '🤏', S.ribbonShort),
            FsPicture(Ribbon.medium, '📏', S.ribbonMedium),
            FsPicture(Ribbon.long, '🎗️', S.ribbonLong),
          ],
          selected: _ribbon,
          onSelect: (v) {
            setState(() => _ribbon = v);
            _next();
          },
        ),
      ],
      _Step.feel => [
        question(S.qFeel),
        FsPictureGrid<Feel>(
          choices: const [
            FsPicture(Feel.gritty, '🏖️', S.feelGritty),
            FsPicture(Feel.smooth, '🌾', S.feelSmooth),
            FsPicture(Feel.neither, '🤲', S.feelNeither),
          ],
          columns: 3,
          selected: _feel,
          onSelect: (v) {
            setState(() => _feel = v);
            _next();
          },
        ),
      ],
      _Step.result => [
        Padding(
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
                Text(
                  _result?.emoji ?? '🤔',
                  style: const TextStyle(fontSize: 64),
                ),
                const SizedBox(height: FsSpace.md),
                Text(S.soilResult, style: t.footnote),
                Text(
                  _result?.label ?? S.dontKnow,
                  style: t.largeTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FsSpace.sm),
                Text(
                  _result == null ? S.soilUnsure : S.soilFromHands,
                  textAlign: TextAlign.center,
                  style: t.body.copyWith(color: p.secondaryLabel),
                ),
              ],
            ),
          ),
        ),
      ],
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
        _Step.intro => FsButton(S.start, onPressed: _next),
        _Step.result => FsButton(
          S.saveSoil,
          icon: CupertinoIcons.checkmark_alt,
          onPressed: _save,
        ),
        _ => FsButton(
          S.dontKnow,
          kind: FsButtonKind.plain,
          onPressed: _unsureNow,
        ),
      },
      children: body,
    );
  }
}
