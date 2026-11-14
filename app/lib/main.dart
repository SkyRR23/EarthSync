import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/strings.dart';
import 'design/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: S.appName,
    debugShowCheckedModeBanner: false,
    theme: fsTheme(),
    routerConfig: _router,
  );
}
