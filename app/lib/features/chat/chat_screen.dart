import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../design/components/earth.dart';
import '../../design/components/page.dart' show FsBackArrow;
import '../../design/components/pressable.dart';
import '../../design/tokens.dart';
import 'chat_state.dart';

/// "Ask EarthSync": chat about this farm. Answers come from Groq on the
/// backend, using only the farm facts the app already shows.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.now});
  final DateTime? now;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _input.clear();
    final facts = farmFacts(ref, widget.now ?? DateTime.now());
    final f = ref.read(chatProvider.notifier).send(text, facts);
    _toEnd();
    await f;
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: FsMotion.of(context, FsMotion.normal),
        curve: FsMotion.curve,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    final s = ref.watch(chatProvider);
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FsSpace.maxContent),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.xs,
                    FsSpace.sm,
                    FsSpace.sm,
                    0,
                  ),
                  child: Row(
                    children: [
                      FsBackArrow(
                        onTap: () => context.canPop()
                            ? context.pop()
                            : context.go('/home'),
                      ),
                      const SizedBox(width: FsSpace.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.chatTitle,
                              style: t.title1.copyWith(fontSize: 24),
                            ),
                            Text(S.chatSubtitle, style: t.footnote),
                          ],
                        ),
                      ),
                      if (s.messages.isNotEmpty)
                        CupertinoButton(
                          padding: const EdgeInsets.all(FsSpace.sm),
                          onPressed: s.sending
                              ? null
                              : ref.read(chatProvider.notifier).clear,
                          child: Semantics(
                            label: S.chatClear,
                            child: Icon(
                              CupertinoIcons.trash,
                              color: p.secondaryLabel,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                      FsSpace.gutter,
                      FsSpace.md,
                      FsSpace.gutter,
                      FsSpace.md,
                    ),
                    children: [
                      if (s.messages.isEmpty) ...[
                        FsEntrance(
                          child: FsCard(
                            margin: EdgeInsets.zero,
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: p.tintSoft,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.eco_rounded,
                                    color: p.tint,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: FsSpace.md),
                                Expanded(
                                  child: Text(S.chatHello, style: t.callout),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: FsSpace.lg),
                        Text(S.chatTry, style: t.headline),
                        const SizedBox(height: FsSpace.sm),
                        for (final (i, q) in S.chatSuggestions.indexed)
                          FsEntrance(
                            index: i + 1,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                bottom: FsSpace.sm,
                              ),
                              child: _Suggestion(
                                text: q,
                                onTap: s.sending ? null : () => _send(q),
                              ),
                            ),
                          ),
                      ],
                      for (final m in s.messages) _Bubble(message: m),
                      if (s.sending) const _Thinking(),
                      if (s.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: FsSpace.sm),
                          child: FsStatusPill(s.error!, tone: FsPillTone.look),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.gutter,
                    0,
                    FsSpace.gutter,
                    FsSpace.xs,
                  ),
                  child: Text(
                    S.chatDisclaimer,
                    textAlign: TextAlign.center,
                    style: t.caption,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FsSpace.gutter,
                    FsSpace.xs,
                    FsSpace.gutter,
                    FsSpace.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 1000,
                          textInputAction: TextInputAction.send,
                          onSubmitted: s.sending ? null : _send,
                          decoration: InputDecoration(
                            hintText: S.chatHint,
                            counterText: '',
                            filled: true,
                            fillColor: p.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: FsSpace.lg,
                              vertical: FsSpace.md,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                FsRadius.capsule,
                              ),
                              borderSide: BorderSide(color: p.separator),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                FsRadius.capsule,
                              ),
                              borderSide: BorderSide(color: p.separator),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: FsSpace.sm),
                      Semantics(
                        button: true,
                        label: S.chatSend,
                        child: FsPressable(
                          onTap: s.sending ? null : () => _send(_input.text),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: s.sending ? p.fill : p.tint,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.arrow_up,
                              color: p.onTint,
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.text, required this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return FsPressable(
      onTap: onTap,
      semanticLabel: text,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FsSpace.lg,
          vertical: FsSpace.md,
        ),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(FsRadius.capsule),
          border: Border.all(color: p.separator),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text, style: context.type.callout)),
            Icon(CupertinoIcons.arrow_up_right, size: 16, color: p.tint),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final me = message.fromUser;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: FsSpace.sm),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FsSpace.lg,
          vertical: FsSpace.md,
        ),
        decoration: BoxDecoration(
          color: me ? p.tint : p.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(FsRadius.xl),
            topRight: const Radius.circular(FsRadius.xl),
            bottomLeft: Radius.circular(me ? FsRadius.xl : 6),
            bottomRight: Radius.circular(me ? 6 : FsRadius.xl),
          ),
          boxShadow: me ? null : FsShadow.soft(p),
        ),
        child: SelectableText(
          message.text,
          style: context.type.callout.copyWith(color: me ? p.onTint : p.label),
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: FsSpace.sm),
    child: Row(
      children: [
        const CupertinoActivityIndicator(),
        const SizedBox(width: FsSpace.sm),
        Text(S.chatThinking, style: context.type.subhead),
      ],
    ),
  );
}
