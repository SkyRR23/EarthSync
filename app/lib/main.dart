import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/strings.dart';
import 'design/theme.dart';
import 'state/preferences_provider.dart';
import 'state/local_farm_provider.dart';
import 'data/local/reminder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FieldShiftApp()));
}

class FieldShiftApp extends ConsumerStatefulWidget {
  const FieldShiftApp({super.key});

  @override
  ConsumerState<FieldShiftApp> createState() => _FieldShiftAppState();
}

class _FieldShiftAppState extends ConsumerState<FieldShiftApp>
    with WidgetsBindingObserver {
  final _router = buildRouter();
  late final DeviceReminders _reminders;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminders = ref.read(deviceRemindersProvider);
    _reminders.onOpen = (route) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _router.go(route);
      });
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(reminderReconciliationProvider);
      ref.read(localRevisionProvider.notifier).changed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminders.onOpen = null;
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(reminderReconciliationProvider);
    return MaterialApp.router(
      title: S.appName,
      debugShowCheckedModeBanner: false,
      theme: fsTheme(),
      darkTheme: fsTheme(brightness: Brightness.dark),
      themeMode:
          ref.watch(preferencesProvider).value?.theme ?? ThemeMode.system,
      locale: Locale(ref.watch(preferencesProvider).value?.language ?? 'en'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('my')],
      routerConfig: _router,
    );
  }
}
