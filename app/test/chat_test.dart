import 'dart:convert';

import 'package:earthsync/app/strings.dart';
import 'package:earthsync/design/theme.dart';
import 'package:earthsync/features/chat/chat_screen.dart';
import 'package:earthsync/features/chat/chat_state.dart';
import 'package:earthsync/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(ProviderContainer, List<Map<String, dynamic>>)> _pump(
  WidgetTester t,
  http.Response Function(Map<String, dynamic> body) answer,
) async {
  t.view.physicalSize = const Size(412 * 3, 915 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({
    'farmer_draft_v1': jsonEncode(
      const FarmerDraft(
        latitude: 16.8512,
        longitude: 96.1534,
        currentCrop: 'rice',
        crops: ['rice', 'mung_bean'],
        farmName: 'Secret name',
      ).toJson(),
    ),
  });
  final prefs = await SharedPreferences.getInstance();
  final sent = <Map<String, dynamic>>[];
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      chatClientProvider.overrideWithValue(
        ChatClient(
          baseUrl: 'https://example.test',
          client: MockClient((r) async {
            final b = jsonDecode(r.body) as Map<String, dynamic>;
            sent.add(b);
            return answer(b);
          }),
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: fsLightTheme(),
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ChatScreen(now: DateTime(2026, 11, 15, 10)),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (c, sent);
}

void main() {
  testWidgets('a suggestion is answered, with farm facts sent', (t) async {
    final (c, sent) = await _pump(
      t,
      (_) => http.Response(
        jsonEncode({'status': 'success', 'reply': 'Feel the soil first.'}),
        200,
      ),
    );
    expect(find.text(S.chatHello), findsOneWidget);
    await t.tap(find.text(S.chatSuggestions.first));
    await t.pumpAndSettle();

    expect(find.text(S.chatSuggestions.first), findsOneWidget); // now a bubble
    expect(find.text('Feel the soil first.'), findsOneWidget);
    final body = sent.single;
    expect(body['messages'], [
      {'role': 'user', 'content': S.chatSuggestions.first},
    ]);
    final farm = (body['farm'] as Map).cast<String, String>();
    expect(farm['crops grown'], 'Rice, Mung bean');
    expect(farm['area'], 'Myanmar, near 16.85, 96.15'); // rounded
    expect(farm.values.join(' '), isNot(contains('Secret name')));
    expect(farm['crop advice'], S.cropsUnknownTitle);
    expect(c.read(chatProvider).messages, hasLength(2));
    expect(t.takeException(), isNull);
  });

  testWidgets('typed question; a server problem is said plainly', (t) async {
    final (c, _) = await _pump(
      t,
      (_) => http.Response(
        jsonEncode({
          'status': 'error',
          'error': {'code': 'not_configured'},
        }),
        503,
      ),
    );
    await t.enterText(find.byType(TextField), 'Is rain coming?');
    await t.tap(find.bySemanticsLabel(S.chatSend));
    await t.pumpAndSettle();
    expect(find.text('Is rain coming?'), findsOneWidget);
    expect(find.text(S.chatNotSetUp), findsOneWidget);
    expect(c.read(chatProvider).sending, false);
  });
}
