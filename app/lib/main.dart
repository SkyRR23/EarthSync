import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/strings.dart';
import 'data/cloud/cloud_sync.dart';
import 'data/engine/rust_engine.dart';
import 'firebase_options.dart';
import 'design/theme.dart';
import 'state/account.dart';
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
  // Firebase is optional: if it cannot start, everything still works and
  // stays on the phone.
  FirebaseAuth? auth;
  CloudSync? cloud;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    auth = FirebaseAuth.instance;
    cloud = CloudSync(FirebaseFirestore.instance, auth);
  } catch (e) {
    debugPrint('Firebase not started: $e');
  }
  final setupDone = loadSavedDraft(prefs).isComplete;
  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        authProvider.overrideWithValue(auth),
        cloudSyncProvider.overrideWithValue(cloud),
      ],
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
