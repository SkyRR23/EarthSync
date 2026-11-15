import 'dart:convert';

import 'package:earthsync/app/strings.dart';
import 'package:earthsync/data/environment/recent_conditions.dart';
import 'package:earthsync/data/models/farmer_input.dart';
import 'package:earthsync/data/models/field_note.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/home/home_tab.dart';
import 'package:earthsync/features/today/farm_tasks.dart';
import 'package:earthsync/state/providers.dart';
import 'package:earthsync/state/today.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final now = DateTime(2026, 11, 15, 9);
const farm = FarmerDraft(latitude: 16.85, longitude: 96.15);

/// The real backend answer for Yangon on 15 Nov 2026 (NASA up to 11 Nov).
const yangon = {
  'status': 'success',
  'as_of': '2026-11-11',
  'past_years': 10,
  'rain_7d_mm': 57.97,
  'rain_7d_vs_past': 'more',
  'root_wetness': 0.74,
  'root_wetness_vs_past': 'drier',
  'heaviest_day': {
    'date': '2026-11-11',
    'rain_mm': 16.35,
    'heavier_than_percent': 98,
    'unusual': true,
  },
};

RecentConditions recent({
  String rain = 'usual',
  String wet = 'usual',
  bool unusual = false,
}) => RecentConditions.fromJson({
  ...yangon,
  'rain_7d_vs_past': rain,
  'root_wetness_vs_past': wet,
  'heaviest_day': {...yangon['heaviest_day'] as Map, 'unusual': unusual},
}, fetchedAt: now);

List<FarmTask> tasks({
  FarmerDraft draft = farm,
  RecentConditions? r,
  List<DateTime> log = const [],
  List<FieldNote> notes = const [],
  Map<String, String> marks = const {},
  bool photos = true,
}) => buildTasks(
  draft: draft,
  recent: r,
  waterLog: log,
  notes: notes,
  marks: marks,
  now: now,
  canTakePhotos: photos,
);

FarmTask water(List<FarmTask> t) =>
    t.firstWhere((x) => x.kind == TaskKind.water);

void main() {
  group('water advice uses only data and the farmer, never amounts', () {
    test('more rain than usual: can likely wait', () {
      final w = water(tasks(r: recent(rain: 'more')));
      expect(w.verdict, WaterVerdict.canWait);
      expect(w.title, S.waterCanWait);
      expect(w.facts.first, S.rainWeek(58, S.moreThanUsual));
      expect(w.facts.last, S.feelFirst);
      expect(w.facts.join(' '), isNot(contains('litre')));
      expect(w.source, S.nasaRecentSource('11 Nov'));
    });

    test('less rain and drier soil: may need water', () {
      final w = water(
        tasks(
          r: recent(rain: 'less', wet: 'drier'),
        ),
      );
      expect(w.verdict, WaterVerdict.mayNeed);
      expect(w.facts, contains(S.wetnessDrier));
    });

    test('mixed signals (real Yangon today): check by hand', () {
      final w = water(
        tasks(
          r: recent(rain: 'more', wet: 'drier'),
        ),
      );
      expect(w.verdict, WaterVerdict.check);
      expect(w.title, S.waterCheck);
    });

    test('no NASA data: says so, still asks for the hand check', () {
      final w = water(tasks());
      expect(w.facts.first, S.waterNoData);
      expect(w.facts.last, S.feelFirst);
      expect(w.source, isNull);
    });

    test('soil type and the watering log are part of the advice', () {
      final sandy = water(
        tasks(
          draft: farm.copyWith(soilTexture: 'loamy_sand'),
          r: recent(),
          log: [DateTime(2026, 11, 12)],
        ),
      );
      expect(sandy.facts, contains(S.sandyDries));
      expect(sandy.facts, contains(S.lastWatered(S.daysAgo(3))));
      final clay = water(tasks(draft: farm.copyWith(soilTexture: 'clay')));
      expect(clay.facts, contains(S.clayHolds));
      expect(clay.facts, contains(S.noWateringYet));
    });

    test('watered today, or soil still wet today, moves it to done', () {
      final a = water(tasks(log: [DateTime(2026, 11, 15)]));
      expect((a.done, a.title), (true, S.wateredToday));
      final b = water(tasks(marks: {'water_ok': '2026-11-15'}));
      expect((b.done, b.title), (true, S.soilStillWetToday));
      // Yesterday's "still wet" does not count today.
      expect(water(tasks(marks: {'water_ok': '2026-11-14'})).done, false);
    });

    test('rain-only field gets no watering task', () {
      final t = tasks(draft: farm.copyWith(irrigation: Irrigation.none));
      expect(t.where((x) => x.kind == TaskKind.water), isEmpty);
    });
  });

  group('heavy rain', () {
    test('unusual rain + water stays: first task, with the facts', () {
      final t = tasks(
        draft: farm.copyWith(drainage: Drainage.poor),
        r: recent(unusual: true),
      );
      expect(t.first.kind, TaskKind.heavyRain);
      expect(t.first.facts, [
        S.heavyFact('11 Nov', 16, 98),
        S.heavyYouSaid,
        S.heavyWalk,
      ]);
    });

    test('good drainage, or ordinary rain: no task', () {
      bool has(List<FarmTask> t) => t.any((x) => x.kind == TaskKind.heavyRain);
      expect(
        has(
          tasks(
            draft: farm.copyWith(drainage: Drainage.good),
            r: recent(unusual: true),
          ),
        ),
        false,
      );
      expect(has(tasks(r: recent())), false);
    });

    test('checked for that rain day: done', () {
      final t = tasks(
        r: recent(unusual: true),
        marks: {'heavy_checked': '2026-11-11'},
      );
      final h = t.firstWhere((x) => x.kind == TaskKind.heavyRain);
      expect((h.done, h.title), (true, S.heavyChecked));
    });
  });

  group('soil and photo reminders', () {
    test('soil: never checked, a season ago, recently', () {
      FarmTask soil(FarmerDraft d) =>
          tasks(draft: d).firstWhere((x) => x.kind == TaskKind.soil);
      expect(soil(farm).facts, [S.soilTaskNew]);
      final old = soil(
        farm.copyWith(soilTexture: 'loam', soilCheckedOn: DateTime(2026, 6, 1)),
      );
      expect((old.done, old.title), (false, S.soilAgainTitle));
      final fresh = soil(
        farm.copyWith(
          soilTexture: 'loam',
          soilCheckedOn: DateTime(2026, 11, 10),
        ),
      );
      expect((fresh.done, fresh.title), (true, S.soilCheckedOn('10 Nov')));
    });

    test('photo: weekly, and only where the phone can take photos', () {
      FieldNote photo(DateTime at) => FieldNote(
        id: 'p',
        createdAt: at,
        kind: NoteKind.growth,
        text: '',
        photo: 'p.jpg',
      );
      FarmTask ph(List<FieldNote> n) =>
          tasks(notes: n).firstWhere((x) => x.kind == TaskKind.photo);
      expect(ph([]).facts, [S.photoNone]);
      expect(ph([photo(DateTime(2026, 11, 12))]).done, true);
      expect(ph([photo(DateTime(2026, 11, 5))]).facts, [S.photoOld(10)]);
      expect(
        tasks(photos: false).where((x) => x.kind == TaskKind.photo),
        isEmpty,
      );
    });

    test('to-do tasks come before done ones', () {
      final t = tasks(log: [DateTime(2026, 11, 15)]);
      final firstDone = t.indexWhere((x) => x.done);
      expect(t.skip(firstDone).every((x) => x.done), true);
    });
  });

  group('NASA recent-days client and offline copy', () {
    test('reads the backend answer', () async {
      late Uri asked;
      final c = RecentClient(
        baseUrl: 'https://example.test',
        client: MockClient((req) async {
          asked = req.url;
          return http.Response(jsonEncode(yangon), 200);
        }),
      );
      final (_, r) = await c.fetch(16.85, 96.15);
      expect(asked.path, '/api/v1/environment/recent');
      expect(asked.queryParameters['latitude'], '16.85000');
      expect(r.asOf, DateTime(2026, 11, 11));
      expect(r.rainVsPast, Compared.higher);
      expect(r.wetnessVsPast, Compared.lower);
      expect(r.heaviestUnusual, true);
    });

    test('keeps the last good copy for when there is no signal', () async {
      SharedPreferences.setMockInitialValues({
        'farmer_draft_v1': jsonEncode(farm.toJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      var online = true;
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          recentClientProvider.overrideWithValue(
            RecentClient(
              baseUrl: 'https://example.test',
              client: MockClient(
                (_) async => online
                    ? http.Response(jsonEncode(yangon), 200)
                    : throw Exception('no signal'),
              ),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(recentProvider.notifier).refresh();
      expect(c.read(recentProvider).data?.rain7dMm, 57.97);

      online = false;
      final again = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          recentClientProvider.overrideWithValue(
            RecentClient(
              baseUrl: 'https://example.test',
              client: MockClient((_) async => throw Exception('no signal')),
            ),
          ),
        ],
      );
      addTearDown(again.dispose);
      expect(again.read(recentProvider).fromCache, true);
      await again.read(recentProvider.notifier).refresh();
      final s = again.read(recentProvider);
      expect((s.failed, s.fromCache, s.data?.rain7dMm), (true, true, 57.97));
    });
  });

  testWidgets('Today tab: tick "I watered today", see it done, undo it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'farmer_draft_v1': jsonEncode(farm.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        recentClientProvider.overrideWithValue(
          RecentClient(
            baseUrl: 'https://example.test',
            client: MockClient(
              (_) async => http.Response(jsonEncode(yangon), 200),
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: fsLightTheme(),
          home: HomeTab(now: now),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(S.waterCheck), findsOneWidget);
    expect(find.text(S.rainWeek(58, S.moreThanUsual)), findsOneWidget);
    expect(find.text(S.heavyTitle), findsOneWidget); // drainage not answered
    expect(find.text(S.soilTitle), findsWidgets);

    await tester.tap(find.text(S.iWatered));
    await tester.pumpAndSettle();
    expect(find.text(S.wateredToday), findsOneWidget);
    expect(find.text(S.waterCheck), findsNothing);
    expect(prefs.getStringList('water_log'), ['2026-11-15']);

    await tester.tap(find.text(S.undo));
    await tester.pumpAndSettle();
    expect(find.text(S.waterCheck), findsOneWidget);
    expect(prefs.getStringList('water_log'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
