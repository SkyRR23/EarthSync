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

/// "What's new"-style welcome: app mark, promise, three steps, one action.
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: p.tint,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      CupertinoIcons.globe,
                      color: p.onTint,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: FsSpace.xxl),
                Text(S.appName, style: t.headline.copyWith(color: p.tint)),
                const SizedBox(height: FsSpace.xs),
                Semantics(
                  header: true,
                  child: Text(S.welcomeTitle, style: t.largeTitle),
                ),
                const SizedBox(height: FsSpace.xxxl),
                const _Feature(
                  icon: CupertinoIcons.location_solid,
                  title: S.how1Title,
                  body: S.how1Body,
                ),
                const _Feature(
                  icon: CupertinoIcons.list_bullet,
                  title: S.how2Title,
                  body: S.how2Body,
                ),
                const _Feature(
                  icon: CupertinoIcons.arrow_right_arrow_left,
                  title: S.how3Title,
                  body: S.how3Body,
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: FsBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              S.welcomeDisclaimer,
              textAlign: TextAlign.center,
              style: t.footnote,
            ),
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

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    return Padding(
      padding: const EdgeInsets.only(bottom: FsSpace.xxl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 40, child: Icon(icon, color: p.tint, size: 28)),
          const SizedBox(width: FsSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.type.headline),
                const SizedBox(height: FsSpace.xxs),
                Text(
                  body,
                  style: context.type.callout.copyWith(color: p.secondaryLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
