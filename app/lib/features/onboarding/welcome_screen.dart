import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../design/components/buttons.dart';
import '../../design/components/page.dart';
import '../../design/tokens.dart';
import '../../state/providers.dart';

/// First-run welcome: promise, three steps, one button.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.fs;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                FsSpace.xxxl,
                FsSpace.huge,
                FsSpace.xxxl,
                FsSpace.xxl,
              ),
              children: [
                const Text('🌾', style: TextStyle(fontSize: 56)),
                const SizedBox(height: FsSpace.lg),
                Text(S.appName, style: t.headline.copyWith(color: p.tint)),
                const SizedBox(height: FsSpace.xs),
                Semantics(
                  header: true,
                  child: Text(S.welcomeTitle, style: t.largeTitle),
                ),
                const SizedBox(height: FsSpace.xxxl),
                const _Step(n: 1, icon: CupertinoIcons.location_solid, text: S.how1),
                const _Step(n: 2, icon: CupertinoIcons.hand_point_right_fill, text: S.how2),
                const _Step(n: 3, icon: CupertinoIcons.checkmark_seal_fill, text: S.how3),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: FsBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(S.welcomeDisclaimer, textAlign: TextAlign.center, style: t.footnote),
            const SizedBox(height: FsSpace.md),
            FsButton(S.getStarted, onPressed: () => context.push('/location')),
            if (kDebugMode)
              FutureBuilder<String>(
                future: ref.read(engineProvider).engineVersion(),
                builder: (_, snap) => Padding(
                  padding: const EdgeInsets.only(top: FsSpace.sm),
                  child: Text(
                    'Engine: ${snap.data ?? '…'}',
                    style: t.caption.copyWith(color: p.tertiaryLabel),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.icon, required this.text});
  final int n;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Padding(
      padding: const EdgeInsets.only(bottom: FsSpace.xl),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: p.tintSoft, shape: BoxShape.circle),
            child: Icon(icon, color: p.tint, size: 22),
          ),
          const SizedBox(width: FsSpace.lg),
          Expanded(
            child: Text(
              text,
              style: context.type.title3,
              semanticsLabel: 'Step $n: $text',
            ),
          ),
        ],
      ),
    );
  }
}
