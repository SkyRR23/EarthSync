import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/strings.dart';
import '../../data/models/field_note.dart';
import '../../design/components/buttons.dart';
import '../../design/components/grouped.dart';
import '../../design/components/page.dart';
import '../../design/components/picture_tiles.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

String noteEmoji(NoteKind kind) => switch (kind) {
  NoteKind.pests => '🐛',
  NoteKind.water => '💧',
  NoteKind.growth => '🌱',
  NoteKind.weather => '☁️',
  NoteKind.other => '📝',
};

String noteLabel(NoteKind kind) => switch (kind) {
  NoteKind.pests => S.kindPests,
  NoteKind.water => S.kindWater,
  NoteKind.growth => S.kindGrowth,
  NoteKind.weather => S.kindWeather,
  NoteKind.other => S.kindOther,
};

/// Notes tab (OpenFarm "scouting" idea): tap what you saw, words optional.
/// Notes stay on this phone.
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
      builder: (_) => _AddNoteSheet(
        kind: kind,
        onSave: (text) => ref.read(notesProvider.notifier).add(kind, text),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.fs;
    final notes = ref.watch(notesProvider);

    return FsPage(
      title: S.notesTitle,
      showBack: false,
      children: [
        FsPictureGrid<NoteKind>(
          choices: [
            for (final k in [
              NoteKind.pests,
              NoteKind.water,
              NoteKind.growth,
              NoteKind.weather,
            ])
              FsPicture(k, noteEmoji(k), noteLabel(k)),
          ],
          unsure: FsPicture(
            NoteKind.other,
            noteEmoji(NoteKind.other),
            noteLabel(NoteKind.other),
          ),
          selected: null,
          tileHeight: 96,
          onSelect: (k) => _add(context, ref, k),
        ),
        if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FsSpace.gutter,
              FsSpace.xl,
              FsSpace.gutter,
              0,
            ),
            child: Text(
              S.notesEmptyBody,
              textAlign: TextAlign.center,
              style: context.type.body.copyWith(color: p.secondaryLabel),
            ),
          )
        else
          FsGroupedSection(
            header: S.yourNotes,
            separatorIndent: FsSpace.lg + 26 + FsSpace.md,
            children: [
              for (final note in notes)
                Dismissible(
                  key: ValueKey(note.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: p.negativeText,
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
            ],
          ),
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow(this.note);
  final FieldNote note;

  @override
  Widget build(BuildContext context) {
    final label = noteLabel(note.kind);
    final text = note.text.isEmpty ? label : note.text;
    final date = DateFormat('d MMM').format(note.createdAt);
    return FsListRow(
      leading: Text(noteEmoji(note.kind), style: const TextStyle(fontSize: 26)),
      title: text,
      titleMaxLines: 3,
      subtitle: note.text.isEmpty ? date : '$label · $date',
      chevron: false,
      semanticLabel: '$label note, $date: $text',
    );
  }
}

class _AddNoteSheet extends StatefulWidget {
  const _AddNoteSheet({required this.kind, required this.onSave});
  final NoteKind kind;
  final ValueChanged<String> onSave;

  @override
  State<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends State<_AddNoteSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
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
                    onPressed: () => Navigator.of(context).pop(),
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
                onPressed: () {
                  widget.onSave(_controller.text);
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
