import 'package:earthsync/app/router.dart';
import 'package:earthsync/design/app_shell.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/main.dart';
import 'package:earthsync/state/home_provider.dart';
import 'package:earthsync/state/integration_provider.dart';
import 'package:earthsync/state/local_farm_provider.dart';
import 'package:earthsync/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
    testWidgets(
      'all product destinations handle unavailable services at $width',
      (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final router = buildRouter()..go('/dashboard');
        final localStore = await memoryFarmStore(t);
        addTearDown(router.dispose);
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              localFarmStoreProvider.overrideWith((ref) async => localStore),
              profileStoreProvider.overrideWithValue(
                MemoryProfileStore(confirmedProfile()),
              ),
              integrationHttpProvider.overrideWithValue(
                MockClient((_) async => http.Response('{}', 503)),
              ),
            ],
            child: MaterialApp.router(theme: fsTheme(), routerConfig: router),
          ),
        );
        for (final route in [
          '/dashboard',
          '/field',
          '/weather',
          '/tasks',
          '/notifications',
          '/local-records',
          '/local-data',
          '/explore',
          '/assessment',
          '/photos',
          '/assistant',
          '/sources',
          '/settings',
          '/question/1',
          '/review',
          '/results',
          '/scenario/unknown',
        ]) {
          router.go(route);
          await t.pumpAndSettle();
          expect(find.byType(AppShell), findsOneWidget, reason: route);
          expect(
            find.byType(NavigationBar),
            width < FsLayout.rail ? findsOneWidget : findsNothing,
            reason: route,
          );
          expect(t.takeException(), isNull, reason: '$route at $width');
        }
      },
    );
  }
  testWidgets(
    'large text and dark mode retain source and navigation semantics',
    (t) async {
      t.view.physicalSize = const Size(320, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final semantics = t.ensureSemantics();
      final router = buildRouter()..go('/sources');
      addTearDown(router.dispose);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            profileStoreProvider.overrideWithValue(MemoryProfileStore()),
          ],
          child: MaterialApp.router(
            theme: fsTheme(brightness: Brightness.dark),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('No location-specific evidence loaded'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No location-specific evidence loaded'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Home')), findsWidgets);
      expect(t.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets(
    'appearance persists and Burmese navigation uses bundled fallback',
    (t) async {
      SharedPreferences.setMockInitialValues({
        'ui.theme': 'dark',
        'ui.language': 'my',
      });
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            profileStoreProvider.overrideWithValue(MemoryProfileStore()),
          ],
          child: const FieldShiftApp(),
        ),
      );
      await t.pumpAndSettle();
      final app = t.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.locale?.languageCode, 'my');
      expect(
        app.theme?.textTheme.bodyMedium?.fontFamilyFallback,
        contains('NotoSansMyanmar'),
      );
      expect(t.takeException(), isNull);
    },
  );
}
