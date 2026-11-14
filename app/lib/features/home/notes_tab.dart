import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/strings.dart';
import '../../data/models/field_note.dart';
import '../../design/components/buttons.dart';
import '../../design/components/grouped.dart';
import '../../design/components/page.dart';
import '../../design/components/pressable.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

String _kindEmoji(NoteKind kind) => switch (kind) {
  NoteKind.pests => '🐛',
  NoteKind.water => '💧',
  NoteKind.growth => '🌱',
  NoteKind.weather => '☁️',
  NoteKind.other => '📝',
};

String _kindLabel(NoteKind kind) => switch (kind) {
  NoteKind.pests => S.kindPests,
  NoteKind.water => S.kindWater,
  NoteKind.growth => S.kindGrowth,
  NoteKind.weather => S.kindWeather,
  NoteKind.other => S.kindOther,
};

/// 4th tab: Field diary notes kept on the phone only.
class NotesTab extends ConsumerWidget {
  const NotesTab({super.key});

  void _openAddSheet(BuildContext context, WidgetRef ref) {
    final p = context.fs;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FsRadius.sheet)),
      ),
      builder: (ctx) => _AddNoteSheet(
        onSave: (kind, text) {
          ref.read(notesProvider.notifier).add(kind, text);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.fs;
    final notes = ref.watch(notesProvider);

    return FsPage(
      title: S.tabNotes,
      showBack: false,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(FsSpace.minTouch),
        onPressed: () => _openAddSheet(context, ref),
        child: Semantics(
          label: S.addNote,
          button: true,
          child: Icon(CupertinoIcons.plus, size: 24, color: p.tint),
        ),
      ),
      children: [
        if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FsSpace.xxl,
              FsSpace.xxxl,
              FsSpace.xxl,
              FsSpace.xxl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: p.tintSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.book,
                        size: 34,
                        color: p.tint,
                      ),
                    ),
                    const SizedBox(height: FsSpace.xl),
                    Text(
                      S.notesEmptyTitle,
                      textAlign: TextAlign.center,
                      style: context.type.title2,
                    ),
                    const SizedBox(height: FsSpace.sm),
                    Text(
                      S.notesEmptyBody,
                      textAlign: TextAlign.center,
                      style: context.type.body.copyWith(
                        color: p.secondaryLabel,
                      ),
                    ),
                    const SizedBox(height: FsSpace.xxl),
                    FsButton(
                      S.addNote,
                      onPressed: () => _openAddSheet(context, ref),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          FsGroupedSection(
            separatorIndent: FsSpace.lg + 22 + FsSpace.md,
            children: [
              for (final note in notes)
                Dismissible(
                  key: ValueKey(note.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: p.negativeText,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: FsSpace.xl),
                    child: const Icon(CupertinoIcons.trash, color: Colors.white),
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
                  child: FsListRow(
                    leading: Text(
                      _kindEmoji(note.kind),
                      style: const TextStyle(fontSize: 22),
                    ),
                    title: note.text,
                    titleMaxLines: 3,
                    subtitle:
                        '${_kindLabel(note.kind)} · ${DateFormat('d MMM, h:mm a').format(note.createdAt)}',
                    chevron: false,
                    semanticLabel:
                        '${_kindLabel(note.kind)} note, ${DateFormat('d MMM').format(note.createdAt)}: ${note.text}',
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _AddNoteSheet extends StatefulWidget {
  const _AddNoteSheet({required this.onSave});
  final void Function(NoteKind kind, String text) onSave;

  @override
  State<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends State<_AddNoteSheet> {
  late final TextEditingController _controller;
  NoteKind _selectedKind = NoteKind.other;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final canSave = _controller.text.trim().isNotEmpty;

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
                  Expanded(
                    child: Text(S.newNote, style: context.type.title3),
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
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FsSpace.lg),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final kind in NoteKind.values) ...[
                      _KindChip(
                        kind: kind,
                        selected: _selectedKind == kind,
                        onTap: () => setState(() => _selectedKind = kind),
                      ),
                      const SizedBox(width: FsSpace.sm),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: FsSpace.lg),
              CupertinoTextField(
                controller: _controller,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                placeholder: S.noteHint,
                placeholderStyle: context.type.body.copyWith(
                  color: p.tertiaryLabel,
                ),
                style: context.type.body.copyWith(color: p.label),
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
                onPressed: canSave
                    ? () {
                        widget.onSave(_selectedKind, _controller.text);
                        Navigator.of(context).pop();
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final NoteKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Semantics(
      button: true,
      selected: selected,
      label: _kindLabel(kind),
      child: FsPressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: FsSpace.minTouch),
          padding: const EdgeInsets.symmetric(
            horizontal: FsSpace.md,
            vertical: FsSpace.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? p.tintSoft : p.surface,
            borderRadius: BorderRadius.circular(FsRadius.capsule),
            border: Border.all(
              color: selected ? p.tint : p.separator,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_kindEmoji(kind)),
              const SizedBox(width: FsSpace.xs),
              Text(
                _kindLabel(kind),
                style: context.type.footnote.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? p.tint : p.label,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

