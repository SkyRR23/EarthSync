import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:earthsync/data/engine/engine_envelope.dart';
import 'package:earthsync/data/models/integration_trace.dart';
import 'package:earthsync/features/assistant/assistant_client.dart';
import 'package:earthsync/features/assistant/assistant_context_adapter.dart';
import 'package:earthsync/features/assistant/assistant_models.dart';
import 'package:earthsync/features/assistant/assistant_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('../docs/assistant/$name.v1.json').readAsStringSync())
        as Map<String, dynamic>;
AssistantContext testContext([String id = 'region-a']) =>
    AssistantContext(contextId: id);
AssistantAnswer testAnswer(
  String id, {
  String text = 'No evidence supplied.',
}) => AssistantAnswer(
  contextId: id,
  language: 'en',
  intent: 'area',
  claims: [
    AssistantClaim(category: AssistantCategory.unavailableEvidence, text: text),
  ],
);

class DeferredAssistant implements AssistantService {
  final calls = <Completer<AssistantAnswer>>[];
  final contexts = <AssistantContext>[];
  @override
  Future<AssistantAnswer> ask({
    required String question,
    required AssistantContext context,
    String language = 'en',
    bool expanded = false,
  }) {
    contexts.add(context);
    final call = Completer<AssistantAnswer>();
    calls.add(call);
    return call.future;
  }
}

Widget host(AssistantContext context, AssistantService service) => MaterialApp(
  home: FarmerAssistantScreen(context: context, service: service),
);

void main() {
  test(
    'shared wire fixture preserves null, evidence provenance and citations',
    () {
      final request = fixture('request');
      final context = AssistantContext.fromJson(
        request['context'] as Map<String, dynamic>,
      );
      expect(context.toJson(), request['context']);
      final answer = AssistantAnswer.fromJson(fixture('response'));
      expect(answer.contextId, context.contextId);
      expect(answer.evidence.single.value, isNull);
      expect(answer.evidence.single.kind, AssistantKind.modeled);
      expect(answer.citations.single.id, 'nasa-docs');
      expect(answer.claims.expand((c) => c.sourceIds), contains('nasa-docs'));
    },
  );

  test(
    'context snapshots cannot be mutated by the host after construction',
    () {
      final records = <AssistantEvidence>[];
      final context = AssistantContext(contextId: 'a', evidence: records);
      records.add(
        AssistantEvidence(
          id: 'photo',
          topic: AssistantTopic.photo,
          metric: 'field_photo',
          kind: AssistantKind.observed,
          quality: AssistantQuality.unverified,
          scope: AssistantScope.unlocated,
          value: 'Image supplied without GPS',
        ),
      );
      expect(context.evidence, isEmpty);
      expect(
        () => context.evidence.add(records.single),
        throwsUnsupportedError,
      );
    },
  );

  test('photo location remains optional and never confirms a farm', () {
    final evidence = AssistantEvidence(
      id: 'photo',
      topic: AssistantTopic.photo,
      metric: 'field_photo',
      kind: AssistantKind.observed,
      quality: AssistantQuality.unverified,
      scope: AssistantScope.unlocated,
    );
    final context = AssistantContext(
      contextId: 'photo-only',
      evidence: [evidence],
    );
    expect(context.confirmedFarm, isNull);
    expect(context.evidence.single.toJson()['location_id'], isNull);
  });

  test('unsupported context or dangling response citation fails closed', () {
    expect(
      () => AssistantContext.fromJson({
        'schema_version': 'future',
        'context_id': 'a',
      }),
      throwsFormatException,
    );
    final response = fixture('response');
    response['citations'] = [];
    expect(() => AssistantAnswer.fromJson(response), throwsFormatException);
  });

  test('analysis requires an explicit matching selection', () {
    final analysis = fieldAnalysisFromEnvelope(
      File('test/fixtures/engine_success_envelope.json').readAsStringSync(),
    );
    expect(
      () => assistantContextFromAnalysis(contextId: 'a', analysis: analysis),
      throwsFormatException,
    );
    expect(
      () => assistantContextFromAnalysis(
        contextId: 'a',
        analysis: analysis,
        selectedArea: AssistantSelection(
          id: 'other',
          point: const AssistantPoint(0, 0),
        ),
      ),
      throwsFormatException,
    );
    final context = assistantContextFromAnalysis(
      contextId: 'a',
      analysis: analysis,
      selectedArea: AssistantSelection(
        id: 'region',
        point: AssistantPoint(
          analysis.location.latitude,
          analysis.location.longitude,
        ),
      ),
    );
    expect(context.confirmedFarm, isNull);
    expect(
      context.evidence.every((e) => e.kind == AssistantKind.synthetic),
      isTrue,
    );
    expect(
      context.evidence.every((e) => e.scope == AssistantScope.regional),
      isTrue,
    );
  });

  test(
    'v0.2 and legacy Rust findings retain exact status and scenario order',
    () {
      final legacy = assistantFindingsFromRust(
        File('test/fixtures/engine_success_envelope.json').readAsStringSync(),
      );
      expect(legacy.decisions.map((d) => d.scenarioId), [
        'alternative-a',
        'existing',
        'alternative-b',
      ]);
      expect(
        legacy.decisions.every((d) => d.status == 'insufficient_information'),
        isTrue,
      );
      final raw = File(
        '../engine/tests/fixtures/synthetic_v02_response.json',
      ).readAsStringSync();
      final findings = assistantFindingsFromRust(raw);
      final scenarios = (jsonDecode(raw)['data']['scenarios'] as List);
      expect(
        findings.decisions.map((d) => d.status),
        scenarios.map((s) => s['status']),
      );
      expect(findings.decisions.every((d) => d.synthetic), isTrue);
      expect(findings.sources.every((s) => s.url == null), isTrue);
    },
  );

  test(
    'captured climate adapter retains original links and rejects stale provenance',
    () {
      final capture =
          jsonDecode(
                File('assets/fixtures/nasa_power_real.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final root =
          jsonDecode(
                File(
                  'test/fixtures/engine_success_envelope.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final data = root['data'] as Map<String, dynamic>;
      // Software adapter fixture only: no live NASA request or Rust call is made.
      data['environment'] = capture['environment'];
      data['field']['latitude'] = capture['environment']['latitude'];
      data['field']['longitude'] = capture['environment']['longitude'];
      data['climate']['window'] = capture['environment']['seasonal']['window'];
      data['climate']['rainfall_total_mm'] = 0.04;
      data['climate']['calendar_day_weighted_mean_temperature_c'] =
          28.03655172413793;
      final raw = jsonEncode(root);
      IntegrationTrace trace() => IntegrationTrace(
        backendResponseJson: jsonEncode(capture),
        farmerInputJson: '{}',
        rustRequestJson: '{}',
        rustResultJson: raw,
        retrievalMode: 'captured_real_response',
      );
      final selection = AssistantSelection(
        id: 'region',
        point: const AssistantPoint(16.85, 96.15),
      );
      final context = assistantContextFromAnalysis(
        contextId: 'capture',
        selectedArea: selection,
        analysis: fieldAnalysisFromEnvelope(raw, trace: trace()),
      );
      final rain = context.evidence.first;
      expect(rain.kind, AssistantKind.modeled);
      expect(rain.scope, AssistantScope.regional);
      expect(rain.startDate, '2024-02-01');
      expect(rain.endDate, '2024-02-29');
      final source = context.sources.firstWhere(
        (s) => s.id == rain.sourceIds.single,
      );
      expect(Uri.parse(source.url!).queryParameters['latitude'], '16.85');
      expect(Uri.parse(source.url!).host, 'power.larc.nasa.gov');
      capture['provenance']['query_coordinates']['latitude'] = 0.0;
      expect(
        () => assistantContextFromAnalysis(
          contextId: 'stale',
          selectedArea: selection,
          analysis: fieldAnalysisFromEnvelope(raw, trace: trace()),
        ),
        throwsFormatException,
      );
    },
  );

  test('Rust findings cannot be relabeled as a different selected point', () {
    final raw = File(
      'test/fixtures/engine_success_envelope.json',
    ).readAsStringSync();
    expect(
      () => assistantFindingsFromRust(
        raw,
        expectedPoint: const AssistantPoint(0, 0),
      ),
      throwsFormatException,
    );
  });

  test(
    'HTTP adapter sends typed context and expanded/language flags',
    () async {
      final request = fixture('request');
      final context = AssistantContext.fromJson(
        request['context'] as Map<String, dynamic>,
      );
      final client = MockClient((r) async {
        final body = jsonDecode(r.body);
        expect(body['context'], context.toJson());
        expect(body['expanded'], isTrue);
        expect(body['language'], 'en');
        return http.Response(
          jsonEncode(fixture('response')),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = HttpAssistantService(
        endpoint: Uri.parse('https://example.org/api/assistant/v1/chat'),
        client: client,
      );
      final answer = await service.ask(
        question: 'Rainfall?',
        context: context,
        expanded: true,
      );
      expect(
        answer.citations.single.url,
        startsWith('https://power.larc.nasa.gov/'),
      );
      client.close();
    },
  );

  for (final failure in ['503', 'timeout', 'network', 'malformed', 'context']) {
    test(
      'HTTP $failure never substitutes a successful or demo answer',
      () async {
        final client = MockClient((r) async {
          switch (failure) {
            case '503':
              return http.Response('private upstream failure', 503);
            case 'timeout':
              throw TimeoutException('private');
            case 'network':
              throw http.ClientException('private');
            case 'malformed':
              return http.Response('invalid JSON', 200);
            default:
              return http.Response(
                jsonEncode(fixture('response')),
                200,
                headers: const {
                  'content-type': 'application/json; charset=utf-8',
                },
              );
          }
        });
        final service = HttpAssistantService(
          endpoint: Uri.parse('http://127.0.0.1:8001/api/assistant/v1/chat'),
          client: client,
        );
        await expectLater(
          service.ask(question: 'Rainfall?', context: testContext()),
          throwsA(isA<AssistantUnavailable>()),
        );
        client.close();
      },
    );
  }

  testWidgets('suggestion, loading, response and source details', (
    tester,
  ) async {
    final service = DeferredAssistant();
    await tester.pumpWidget(host(testContext(), service));
    await tester.tap(find.text('What is happening in my area?'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    service.calls.single.complete(testAnswer('region-a'));
    await tester.pumpAndSettle();
    expect(find.text('No evidence supplied.'), findsOneWidget);
    await tester.tap(find.text('Evidence and sources'));
    await tester.pumpAndSettle();
    expect(find.text('No source citations supplied.'), findsOneWidget);
  });

  testWidgets('unavailable service shows retry and preserves the question', (
    tester,
  ) async {
    final service = DeferredAssistant();
    await tester.pumpWidget(host(testContext(), service));
    await tester.enterText(find.byType(TextField), 'Explain the rainfall');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    service.calls.first.completeError(const AssistantUnavailable('503'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The assistant is unavailable.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(service.calls, hasLength(2));
    service.calls.last.complete(testAnswer('region-a'));
    await tester.pumpAndSettle();
    expect(find.text('Explain the rainfall'), findsOneWidget);
  });

  testWidgets(
    'context changes clear history and discard previous in-flight replies',
    (tester) async {
      final service = DeferredAssistant();
      await tester.pumpWidget(host(testContext('old'), service));
      await tester.tap(find.text('What is happening in my area?'));
      await tester.pump();
      await tester.pumpWidget(host(testContext('new'), service));
      service.calls.first.complete(testAnswer('old', text: 'OLD FIELD'));
      await tester.pumpAndSettle();
      expect(find.text('OLD FIELD'), findsNothing);
      await tester.tap(find.text('What is happening in my area?'));
      await tester.pump();
      expect(service.contexts.last.contextId, 'new');
      service.calls.last.complete(testAnswer('new', text: 'NEW CONTEXT'));
      await tester.pumpAndSettle();
      expect(find.text('NEW CONTEXT'), findsOneWidget);
      await tester.pumpWidget(host(testContext('third'), service));
      await tester.pumpAndSettle();
      expect(find.text('NEW CONTEXT'), findsNothing);
    },
  );

  testWidgets('malicious supplied text stays plain selectable text', (
    tester,
  ) async {
    final service = DeferredAssistant();
    await tester.pumpWidget(host(testContext(), service));
    await tester.tap(find.text('What is happening in my area?'));
    await tester.pump();
    service.calls.single.complete(
      testAnswer('region-a', text: '<script>plant_now()</script>'),
    );
    await tester.pumpAndSettle();
    expect(find.text('<script>plant_now()</script>'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
