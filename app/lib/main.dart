import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/strings.dart';
import 'data/engine/rust_engine.dart';
import 'design/theme.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kEngine == 'rust') await RustEngine.init();
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    prefs = null; // storage unavailable: app still works, nothing is saved
  }
  final setupDone = loadSavedDraft(prefs).isComplete;
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: FieldShiftApp(setupDone: setupDone),
    ),
  );
}

class FieldShiftApp extends StatefulWidget {
  const FieldShiftApp({super.key, this.setupDone = false});
  final bool setupDone;

  @override
  State<FieldShiftApp> createState() => _FieldShiftAppState();
}

class _FieldShiftAppState extends State<FieldShiftApp> {
  late final _router = buildRouter(setupDone: widget.setupDone);

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: S.appName,
    debugShowCheckedModeBanner: false,
    theme: fsLightTheme(),
    darkTheme: fsDarkTheme(),
    themeMode: ThemeMode.system,
    routerConfig: _router,
  );
}
