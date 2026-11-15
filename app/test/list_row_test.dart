import 'package:earthsync/data/environment/nasa_power_client.dart';
import 'package:earthsync/design/components/grouped.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/home/field_tab.dart' show windowLabel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _rows({double textScale = 1.0}) => MaterialApp(
  theme: fsDarkTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: ListView(
      children: [
        FsGroupedSection(
          children: [
            FsListRow(
              leading: const Icon(Icons.water_drop),
              title: 'Water',
              value: 'All year',
              onTap: () {},
            ),
            FsListRow(
              leading: const Icon(Icons.cloud),
              title: 'After rain',
              value: '⏳ Stays 1–2 days',
              onTap: () {},
            ),
            FsListRow(
              leading: const Icon(Icons.verified),
              title: 'Saved online',
              value: 'a.very.long.farmer.name@gmail.com',
              chevron: false,
            ),
          ],
        ),
      ],
    ),
  ),
);

double _top(WidgetTester t, String text) => t.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('a short value sits beside its title on one line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_rows());
    expect(
      (_top(tester, 'All year') - _top(tester, 'Water')).abs(),
      lessThan(4),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a long value moves under its title instead of wrapping beside it',
    (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_rows(textScale: 1.3));
      final email = 'a.very.long.farmer.name@gmail.com';
      expect(
        _top(tester, email),
        greaterThan(_top(tester, 'Saved online') + 10),
      );
      // Under the title it starts at the title's left edge, not squeezed right.
      expect(
        (tester.getTopLeft(find.text(email)).dx -
                tester.getTopLeft(find.text('Saved online')).dx)
            .abs(),
        lessThan(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('weather window labels are short', () {
    expect(
      windowLabel(
        const HistoricalWindow(
          startYear: 2025,
          startMonth: 1,
          endYear: 2025,
          endMonth: 12,
        ),
      ),
      '2025',
    );
    expect(
      windowLabel(
        const HistoricalWindow(
          startYear: 2025,
          startMonth: 3,
          endYear: 2025,
          endMonth: 9,
        ),
      ),
      'Mar – Sep 2025',
    );
    expect(
      windowLabel(
        const HistoricalWindow(
          startYear: 2024,
          startMonth: 2,
          endYear: 2024,
          endMonth: 2,
        ),
      ),
      'Feb 2024',
    );
    expect(
      windowLabel(
        const HistoricalWindow(
          startYear: 2024,
          startMonth: 11,
          endYear: 2025,
          endMonth: 2,
        ),
      ),
      'Nov 2024 – Feb 2025',
    );
  });
}
