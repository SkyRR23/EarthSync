import 'package:earthsync/features/companion/environmental_timeline_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'regional soil snapshot keeps date, support and missingness on phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                EnvironmentalTimelineCard(
                  job: {
                    'kind': 'soil_map',
                    'status': 'succeeded',
                    'updated': 1794682706.9411082,
                    'result': {
                      'provider': 'Software test source',
                      'retrieved_at': '2026-11-13',
                      'property': 'pH',
                      'depth_cm': [0, 5],
                      'resolution_m': 250,
                      'unit': 'pH',
                      'cells': [
                        {
                          'at_query_point': true,
                          'value': null,
                          'quality': 'nodata',
                        },
                      ],
                    },
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.textContaining('Environmental context'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('observation time Unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('250 m modeled grid'), findsOneWidget);
      expect(
        find.textContaining('Request saved 2026-11-14T18:58:26.941Z'),
        findsOneWidget,
      );
      expect(
        find.text('Cell at query point: Missing pH · nodata'),
        findsOneWidget,
      );
      expect(
        find.textContaining('not a laboratory measurement'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
