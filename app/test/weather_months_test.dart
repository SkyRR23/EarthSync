import 'package:earthsync/app/strings.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/home/weather_months_picker.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final n = DateTime.now().toUtc();
  final lastDone = DateTime(n.year, n.month - 1);

  test('only finished months, in order, up to 24 are allowed', () {
    final year = lastFullYear();
    expect(
      windowIfValid(
        DateTime(year.startYear, year.startMonth),
        DateTime(year.endYear, year.endMonth),
      ),
      isNotNull,
    );
    expect(windowIfValid(lastDone, lastDone), isNotNull);
    // To before From.
    expect(
      windowIfValid(lastDone, DateTime(lastDone.year, lastDone.month - 1)),
      isNull,
    );
    // 25 months.
    expect(
      windowIfValid(DateTime(lastDone.year, lastDone.month - 24), lastDone),
      isNull,
    );
    // This month is not finished yet.
    expect(windowIfValid(lastDone, DateTime(n.year, n.month)), isNull);
  });

  testWidgets('picker shows From and To wheels and keeps the window', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    final before = c.read(historicalWindowProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: fsLightTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: WeatherMonthsPicker()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(S.weatherFrom), findsOneWidget);
    expect(find.text(S.weatherTo), findsOneWidget);
    expect(find.text(S.weatherMonthsBad), findsNothing);
    expect(identical(c.read(historicalWindowProvider), before), true);
    expect(tester.takeException(), isNull);
  });
}
