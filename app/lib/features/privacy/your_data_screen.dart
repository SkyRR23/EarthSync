import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/strings.dart';
import '../../design/components/grouped.dart';
import '../../design/components/page.dart';
import '../../design/tokens.dart';
import '../../state/account.dart';

/// "Your data": what is kept where, in plain words, and "Delete all my data"
/// (required by Google Play for apps with sign-in).
class YourDataScreen extends ConsumerStatefulWidget {
  const YourDataScreen({super.key});

  @override
  ConsumerState<YourDataScreen> createState() => _YourDataScreenState();
}

class _YourDataScreenState extends ConsumerState<YourDataScreen> {
  bool _busy = false;

  Future<void> _delete() async {
    final signedIn = ref.read(authProvider)?.currentUser != null;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text(S.deleteConfirmTitle),
        content: Text(S.deleteConfirmBody(signedIn: signedIn)),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(S.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.deleteWord),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final error = await deleteMyData(ref);
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.of(context);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text(S.allDeleted)));
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.fs;
    final t = context.type;
    const indent = FsSpace.lg + 30 + FsSpace.md;

    Widget row(String emoji, String title, String body) => FsListRow(
      leading: Text(emoji, style: const TextStyle(fontSize: 26)),
      title: title,
      titleStyle: t.headline,
      subtitle: body,
      chevron: false,
    );

    return FsPage(
      title: S.yourData,
      children: [
        FsGroupedSection(
          separatorIndent: indent,
          children: [
            row('📱', S.dataPhoneTitle, S.dataPhoneBody),
            row('☁️', S.dataOnlineTitle, S.dataOnlineBody),
            row('🔢', S.dataCountsTitle, S.dataCountsBody),
            row('🛰️', S.dataWeatherTitle, S.dataWeatherBody),
            row('🚫', S.dataNeverTitle, S.dataNeverBody),
          ],
        ),
        FsGroupedSection(
          footer: S.deleteFooter,
          children: [
            FsListRow(
              leading: Icon(CupertinoIcons.square_arrow_up, color: p.tint),
              title: 'Export local tasks, plans & evidence',
              onTap: () => context.push('/local-data'),
            ),
            FsListRow(
              leading: _busy
                  ? const CupertinoActivityIndicator()
                  : Icon(CupertinoIcons.trash, color: p.negativeText, size: 22),
              title: S.deleteAll,
              titleStyle: t.body.copyWith(color: p.negativeText),
              chevron: false,
              onTap: _busy ? null : _delete,
            ),
          ],
        ),
      ],
    );
  }
}
