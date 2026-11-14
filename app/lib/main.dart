import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/strings.dart';
import 'design/theme.dart';
import 'state/preferences_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FieldShiftApp()));
}

class FieldShiftApp extends ConsumerStatefulWidget {
  const FieldShiftApp({super.key});

  @override
  ConsumerState<FieldShiftApp> createState() => _FieldShiftAppState();
}

class _FieldShiftAppState extends ConsumerState<FieldShiftApp> {
  final _router = buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: S.appName,
    debugShowCheckedModeBanner: false,
    theme: fsTheme(),
    darkTheme: fsTheme(brightness: Brightness.dark),
    themeMode: ref.watch(preferencesProvider).value?.theme ?? ThemeMode.system,
    locale: Locale(ref.watch(preferencesProvider).value?.language ?? 'en'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('en'), Locale('my')],
    routerConfig: _router,
  );
}
