import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../design/components/buttons.dart';
import '../../design/components/page.dart';
import '../../design/tokens.dart';
import '../../state/account.dart';
import '../../state/providers.dart';

/// "Keep your farm safe": Google sign-in so the farm, answers, notes and
/// results are saved to the farmer's account. "Not now" keeps going offline.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;
  String? _error;

  void _next() {
    final d = ref.read(farmerDraftProvider);
    if (d.isComplete) {
      // A saved farm came back from the cloud: straight to the crops.
      ref.read(analysisProvider.notifier).run(d.toInput());
      context.go('/home');
    } else {
      context.push('/location');
    }
  }

  Future<void> _signIn() async {
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
    if (error == null && ref.read(authProvider)?.currentUser != null) _next();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FsSpace.maxContent),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(FsSpace.xxl),
              children: [
                const Text(
                  '🌾☁️',
                  style: TextStyle(fontSize: 56),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FsSpace.xl),
                Text(
                  S.signInTitle,
                  style: t.largeTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FsSpace.md),
                Text(
                  S.signInBody,
                  style: t.body.copyWith(color: p.secondaryLabel),
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: FsSpace.lg),
                  Text(
                    _error!,
                    style: t.footnote.copyWith(color: p.cautionText),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: FsBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FsButton(
              S.signInGoogle,
              icon: CupertinoIcons.person_crop_circle_fill,
              loading: _busy,
              onPressed: _busy ? null : _signIn,
            ),
            const SizedBox(height: FsSpace.xs),
            FsButton(
              S.notNow,
              kind: FsButtonKind.plain,
              onPressed: _busy ? null : _next,
            ),
          ],
        ),
      ),
    );
  }
}
