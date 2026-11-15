import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../submission/simulation_clock.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../data/models/field_note.dart';
import '../../data/photos/photo_store.dart';
import '../../design/components/buttons.dart';
import '../../design/components/earth.dart';
import '../../design/components/page.dart' show FsBackArrow;
import '../../design/components/picture_tiles.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';
import 'home_shell.dart';

String noteEmoji(NoteKind kind) => switch (kind) {
  NoteKind.pests => '🐛',
  NoteKind.water => '💧',
  NoteKind.growth => '🌱',
  NoteKind.weather => '☁️',
  NoteKind.soil => '🟤',
  NoteKind.other => '📝',
};

String noteLabel(NoteKind kind) => switch (kind) {
  NoteKind.pests => S.kindPests,
  NoteKind.water => S.kindWater,
  NoteKind.growth => S.kindGrowth,
  NoteKind.weather => S.kindWeather,
  NoteKind.soil => S.kindSoil,
  NoteKind.other => S.kindOther,
};

/// Notes tab (OpenFarm "scouting" idea): tap what you saw, add a photo,
/// words optional. Photos are for people to look at; the app measures nothing
/// from them.
class NotesTab extends ConsumerWidget {
  const NotesTab({super.key});

  void _add(BuildContext context, WidgetRef ref, NoteKind kind) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.fs.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FsRadius.sheet),
        ),
      ),
      builder: (_) => AddNoteSheet(kind: kind),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.fs;
    final t = context.type;
    final notes = ref.watch(notesProvider);
    final tabs = HomeTabs.of(context);

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FsSpace.maxContent),
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
                          S.notesTitle,
                          style: t.title1.copyWith(fontSize: 26),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.gutter + FsSpace.xxs,
                    FsSpace.xs,
                    FsSpace.gutter,
                    FsSpace.sm,
                  ),
                  child: Text(
                    S.notesEmptyBody,
                    style: t.body.copyWith(color: p.secondaryLabel),
                  ),
                ),
                FsEntrance(
                  child: FsPictureGrid<NoteKind>(
                    choices: [
                      for (final k in NoteKind.values)
                        if (k != NoteKind.other)
                          FsPicture(k, noteEmoji(k), noteLabel(k)),
                      FsPicture(
                        NoteKind.other,
                        noteEmoji(NoteKind.other),
                        noteLabel(NoteKind.other),
                      ),
                    ],
                    columns: 3,
                    selected: null,
                    tileHeight: 92,
                    onSelect: (k) => _add(context, ref, k),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FsSpace.gutter,
                  ),
                  child: FsButton(
                    'Field history, soil checks & linked tasks',
                    kind: FsButtonKind.tinted,
                    onPressed: () => context.push('/local-records'),
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const FsSectionTitle(S.yourNotes),
                  for (final (i, note) in notes.indexed)
                    FsEntrance(
                      index: i + 1,
                      child: Dismissible(
                        key: ValueKey(note.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.fromLTRB(
                            FsSpace.gutter,
                            FsSpace.md,
                            FsSpace.gutter,
                            0,
                          ),
                          decoration: BoxDecoration(
                            color: p.negativeText,
                            borderRadius: BorderRadius.circular(FsRadius.xl),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: FsSpace.xl),
                          child: const Icon(
                            CupertinoIcons.trash,
                            color: Colors.white,
                          ),
                        ),
                        onDismissed: (_) {
                          final notifier = ref.read(notesProvider.notifier);
                          notifier.remove(note.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(S.deleted),
                              action: SnackBarAction(
                                label: S.undo,
                                onPressed: () => notifier.restore(note),
                              ),
                            ),
                          );
                        },
                        child: _NoteRow(note),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteRow extends ConsumerWidget {
  const _NoteRow(this.note);
  final FieldNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(photoStoreProvider);
    final label = noteLabel(note.kind);
    final text = note.text.isEmpty ? label : note.text;
    final date = DateFormat('d MMM').format(note.createdAt);
    final file = (store != null && note.photo != null)
        ? store.file(note.photo!)
        : null;
    final p = context.fs;
    final t = context.type;
    return FsCard(
      padding: const EdgeInsets.all(FsSpace.md),
      semanticLabel:
          '$label note, $date: $text${file == null ? '' : ', with photo'}',
      onTap: file == null ? null : () => showNotePhoto(context, file),
      child: Row(
        children: [
          if (file == null)
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: p.tintSoft,
                borderRadius: BorderRadius.circular(FsRadius.md),
              ),
              alignment: Alignment.center,
              child: Text(
                noteEmoji(note.kind),
                style: const TextStyle(fontSize: 30),
              ),
            )
          else
            NotePhotoThumb(file: file, size: 64),
          const SizedBox(width: FsSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: t.headline.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: FsSpace.xs),
                Wrap(
                  spacing: FsSpace.sm,
                  runSpacing: FsSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (note.text.isNotEmpty)
                      FsStatusPill(label, tone: FsPillTone.info),
                    Text(
                      date,
                      style: t.subhead.copyWith(color: p.secondaryLabel),
                    ),
                    TextButton.icon(
                      onPressed: () => context.push(Uri(path: '/chat', queryParameters: {'note': note.id}).toString()),
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Ask for next steps'),
                    ),
                    if (note.cloudPhoto != null)
                      Icon(
                        CupertinoIcons.cloud_fill,
                        size: 16,
                        color: p.secondaryLabel,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NotePhotoThumb extends StatelessWidget {
  const NotePhotoThumb({super.key, required this.file, this.size = 52});
  final File file;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(FsRadius.md),
    child: Image.file(
      file,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * 3).round(),
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: const Center(child: Text('🖼️', style: TextStyle(fontSize: 24))),
      ),
    ),
  );
}

void showNotePhoto(BuildContext context, File file) {
  showDialog<void>(
    context: context,
    builder: (ctx) => GestureDetector(
      onTap: () => Navigator.of(ctx).pop(),
      child: InteractiveViewer(
        child: Center(child: Image.file(file, fit: BoxFit.contain)),
      ),
    ),
  );
}

/// Add a note: big photo buttons, optional words, Save.
class AddNoteSheet extends ConsumerStatefulWidget {
  const AddNoteSheet({super.key, required this.kind});
  final NoteKind kind;

  @override
  ConsumerState<AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends ConsumerState<AddNoteSheet> {
  final _controller = TextEditingController();
  final _id = DateTime.now().microsecondsSinceEpoch.toString();
  String? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final store = ref.read(photoStoreProvider);
    if (store == null) return;
    setState(() => _busy = true);
    try {
      final picked = await pickPhoto(source);
      if (picked != null) {
        final old = _photo;
        final name = await store.save(picked, _id);
        if (old != null && old != name) await store.delete(old);
        if (!mounted) return;
        // Bust the image cache: same file name, new picture.
        PaintingBinding.instance.imageCache.evict(FileImage(store.file(name)));
        setState(() => _photo = name);
      }
    } catch (_) {
      // Camera unavailable or permission refused: the note still works.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final store = ref.watch(photoStoreProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: FsSpace.gutter,
          right: FsSpace.gutter,
          top: FsSpace.xl,
          bottom: FsSpace.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    noteEmoji(widget.kind),
                    style: const TextStyle(fontSize: 34),
                  ),
                  const SizedBox(width: FsSpace.md),
                  Expanded(
                    child: Text(noteLabel(widget.kind), style: t.title2),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(FsSpace.minTouch),
                    onPressed: () async {
                      await store?.delete(_photo);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Semantics(
                      button: true,
                      label: S.cancel,
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: p.tertiaryLabel,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
              if (store != null) ...[
                const SizedBox(height: FsSpace.lg),
                if (_photo != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(FsRadius.md),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.file(store.file(_photo!), fit: BoxFit.cover),
                    ),
                  ),
                  FsButton(
                    S.removePhoto,
                    kind: FsButtonKind.plain,
                    onPressed: () async {
                      await store.delete(_photo);
                      setState(() => _photo = null);
                    },
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: FsButton(
                          S.takePhoto,
                          kind: FsButtonKind.tinted,
                          icon: CupertinoIcons.camera_fill,
                          loading: _busy,
                          onPressed: _busy
                              ? null
                              : () => _pick(ImageSource.camera),
                        ),
                      ),
                      const SizedBox(width: FsSpace.sm),
                      Expanded(
                        child: FsButton(
                          S.choosePhoto,
                          kind: FsButtonKind.tinted,
                          icon: CupertinoIcons.photo,
                          onPressed: _busy
                              ? null
                              : () => _pick(ImageSource.gallery),
                        ),
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: FsSpace.lg),
              CupertinoTextField(
                controller: _controller,
                minLines: 3,
                maxLines: 6,
                placeholder: S.noteHint,
                placeholderStyle: t.body.copyWith(color: p.tertiaryLabel),
                style: t.body.copyWith(color: p.label),
                padding: const EdgeInsets.all(FsSpace.md),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(FsRadius.md),
                  border: Border.all(color: p.separator, width: 0.5),
                ),
              ),
              const SizedBox(height: FsSpace.xl),
              FsButton(
                S.save,
                icon: CupertinoIcons.checkmark_alt,
                onPressed: _busy
                    ? null
                    : () {
                        ref
                            .read(notesProvider.notifier)
                            .add(
                              widget.kind,
                              _controller.text,
                              observedOn: kIsWeb ? null : ref.read(simulationClockProvider),
                              photo: _photo,
                              id: _id,
                            );
                        Navigator.of(context).pop();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
