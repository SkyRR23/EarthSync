import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/strings.dart';
import 'data/engine/rust_engine.dart';
import 'design/theme.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kEngine == 'rust') await RustEngine.init();
  runApp(const ProviderScope(child: FieldShiftApp()));
}

class FieldShiftApp extends StatefulWidget {
  const FieldShiftApp({super.key});

  @override
  State<FieldShiftApp> createState() => _FieldShiftAppState();
}

class _FieldShiftAppState extends State<FieldShiftApp> {
  final _router = buildRouter();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: S.appName,
    debugShowCheckedModeBanner: false,
    theme: fsTheme(),
    routerConfig: _router,
  );
}
