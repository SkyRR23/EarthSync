import 'dart:async';

import 'package:earthsync/data/engine/engine_gateway.dart';
import 'package:earthsync/data/models/farmer_input.dart';
import 'package:earthsync/data/models/field_analysis.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingEngine implements EngineGateway {
  final pending = <double, Completer<FieldAnalysis>>{};
  @override
  Future<FieldAnalysis> analyzeField(FarmerInput input) =>
      (pending[input.latitude] = Completer<FieldAnalysis>()).future;
  @override
  Future<String> engineVersion() async => 'test';
}

FieldAnalysis _result(double latitude) => FieldAnalysis(
  location: FieldLocation(latitude: latitude, longitude: 96.15),
  climateSummary: const ClimateSummary(
    months: [],
    period: 'Feb 2024',
    sourceId: 'test',
  ),
  scenarios: const [],
  alerts: const [],
  assumptions: const [],
  dataGaps: const [],
  references: const [],
  dataQuality: const DataQuality(),
);

void main() {
  test(
    'a slow response for the earlier field cannot replace the latest result',
    () async {
      final engine = _PendingEngine();
      final container = ProviderContainer(
        overrides: [engineProvider.overrideWithValue(engine)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(analysisProvider.notifier);
      final first = notifier.run(
        const FarmerInput(latitude: 16.85, longitude: 96.15),
      );
      final second = notifier.run(
        const FarmerInput(latitude: 17.0, longitude: 96.15),
      );
      engine.pending[17.0]!.complete(_result(17.0));
      await second;
      engine.pending[16.85]!.complete(_result(16.85));
      await first;
      expect(
        (container.read(analysisProvider) as AnalysisReady)
            .analysis
            .location
            .latitude,
        17.0,
      );
    },
  );

  test(
    'questionnaire preserves unknown crop and previous crop, month and priorities',
    () {
      const draft = FarmerDraft(
        latitude: 16.85,
        longitude: 96.15,
        currentCrop: kUnknown,
        previousCrop: 'sesame',
        plantingMonth: 6,
        priorities: {Priority.lessWater},
      );
      final input = draft.toInput();
      expect(input.currentCrop, isNull);
      expect(input.recentRotation, ['sesame']);
      expect(input.plantingMonth, 6);
      expect(input.priorities, [Priority.lessWater]);
    },
  );
}
