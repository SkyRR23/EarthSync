import 'package:earthsync/data/farm_journal.dart';
import 'package:earthsync/features/companion/companion_screen.dart';
import 'package:earthsync/state/home_provider.dart';
import 'package:earthsync/state/integration_provider.dart';
import 'package:earthsync/state/journal_provider.dart';
import 'package:earthsync/state/platform_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home_test_support.dart';

void main() {
  for (final language in ['en', 'my']) {
    for (final width in [390.0, 1280.0]) {
      testWidgets('season form and cached timeline $language at $width', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileStoreProvider.overrideWithValue(
                MemoryProfileStore(confirmedProfile()),
              ),
              platformFarmClientProvider.overrideWithValue(null),
              catalogProvider.overrideWith((ref) async => {'profiles': []}),
              journalProvider.overrideWith(
                (ref) async => FarmJournalSnapshot({
                  'farm_id': 'db-farm',
                  'retrieved_at': '2024-01-01T00:00:00Z',
                  'entries': [],
                  'evidence': [],
                  'decisions': [],
                  'photos': [],
                }, cached: true),
              ),
            ],
            child: MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('my')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: const CompanionScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('2024-01-01T00:00:00Z'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byType(RawAutocomplete<String>),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byType(FilterChip).first,
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byType(FilterChip).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text(
            language == 'en'
                ? 'Save draft on this device'
                : 'ဤစက်ပေါ်တွင် မူကြမ်းသိမ်းမည်',
          ),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(
            language == 'en'
                ? 'Save draft on this device'
                : 'ဤစက်ပေါ်တွင် မူကြမ်းသိမ်းမည်',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            language == 'en'
                ? 'Draft saved · not submitted'
                : 'မူကြမ်းသိမ်းပြီး · မတင်ပြရသေး',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
