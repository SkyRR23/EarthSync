import '../../submission/historical_reference.dart';
import '../../submission/simulation_clock.dart';
import '../../data/backend_response.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/strings.dart';
import '../../data/environment/forecast.dart';
import '../../data/environment/recent_conditions.dart';
import '../../data/models/farm_boundary.dart';
import '../../data/models/farmer_input.dart';
import '../../data/models/soil_texture.dart';
import '../../design/components/scenario.dart' show monthNames;
import '../../state/providers.dart';
import '../../state/today.dart';
import '../home/field_tab.dart' show answerDrain, answerWater;
import '../today/farm_tasks.dart' show buildTasks, shortDate;

class ChatMessage {
  const ChatMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;

  Map<String, Object> toJson() => {
    'role': fromUser ? 'user' : 'assistant',
    'content': text,
  };
}

class ChatException implements Exception {
  const ChatException(this.code);
  final String code;
}

/// Talks to the backend's /api/v1/chat (Groq; the key stays on the server).
class ChatClient {
  ChatClient({
    this.baseUrl = const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'https://fieldshift-yangon-2026.web.app',
    ),
    this.client,
    this.timeout = const Duration(seconds: 70),
  });
  final String baseUrl;
  final http.Client? client;
  final Duration timeout;

  Future<String> ask(
    List<ChatMessage> messages,
    Map<String, String> farm,
  ) async {
    final c = client ?? http.Client();
    try {
      final r = await c
          .post(
            Uri.parse(baseUrl).resolve('/api/v1/chat'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'messages': [for (final m in messages) m.toJson()],
              'farm': farm,
              if (!kIsWeb) 'response_mode': 'farmer_first',
            }),
          )
          .timeout(timeout);
      final j = backendJson(r);
      if (j == null) throw ChatException(backendFailure(r));
      if (r.statusCode == 200 && j['status'] == 'success') {
        return j['reply'] as String;
      }
      final e = (j['error'] as Map?) ?? const {};
      throw ChatException(e['code'] is String ? e['code'] as String : backendFailure(r));
    } on ChatException {
      rethrow;
    } catch (_) {
      throw const ChatException('unreachable');
    } finally {
      if (client == null) c.close();
    }
  }
}

final chatClientProvider = Provider<ChatClient>((ref) => ChatClient());

String _plain(String s) =>
    s.replaceAll(RegExp(r'[^\x20-\x7E–’°]'), '').trim(); // drop emoji

String _month(int? m) => m == null || m == 0 ? 'not known' : monthNames[m - 1];

/// The farm facts the chat may use: only what the app already shows. The
/// location is rounded (about 1 km) and the farm name is not sent.
Map<String, String> farmFacts(WidgetRef ref, DateTime now) {
  final d = ref.read(farmerDraftProvider);
  final f = ref.read(forecastProvider).data;
  final r = ref.read(recentProvider).data;
  final et0 = kIsWeb ? ref.read(et0Provider).value : null;
  final green = kIsWeb ? ref.read(greennessProvider).value?.latest : null;
  final log = ref.read(waterLogProvider);
  final soil = soilClassFromName(d.soilTexture);
  final todo = [
    for (final t in buildTasks(
      draft: d,
      recent: r,
      waterLog: log,
      notes: ref.read(notesProvider),
      marks: ref.read(taskMarksProvider),
      now: now,
      canTakePhotos: ref.read(photoStoreProvider) != null,
      et0: et0,
      alerts: ref.read(alertPrefsProvider),
    ))
      if (!t.done) t.title,
  ];
  String compared(Compared c, String lower, String higher) => switch (c) {
    Compared.lower => lower,
    Compared.higher => higher,
    Compared.usual => 'about usual for this time of year',
    Compared.unknown => 'not known',
  };
  final facts = {
    'today': shortDate(now),
    'area': d.fieldLatitude == null
        ? 'not set'
        : 'Myanmar, near ${d.fieldLatitude!.toStringAsFixed(2)}, ${d.fieldLongitude!.toStringAsFixed(2)}',
    'crops grown': d.crops.isNotEmpty
        ? d.crops.map(Crops.label).join(', ')
        : (d.currentCrop == null || d.currentCrop == kUnknown
              ? 'not answered'
              : Crops.label(d.currentCrop)),
    'farm type': d.farmType ?? 'crop',
    'farm size': d.hasFarm ? farmSizeLabel(d.farm!) : 'corners not marked',
    'planting month': _month(d.plantingMonth),
    'harvest month': _month(d.harvestMonth),
    'watering': _plain(answerWater(d.irrigation)),
    'after heavy rain the field': _plain(answerDrain(d.drainage)),
    'soil type': soil == null
        ? 'not checked'
        : '${soil.label} (${d.soilSource == 'ai_estimate' ? 'AI estimate from photos' : 'farmer hand test'})',
    if (d.soilSigns.isNotEmpty) 'soil signs': d.soilSigns.join(', '),
    if (f != null) ...{
      'weather now (forecast)': [
        if (f.current.tempC != null) '${f.current.tempC!.round()}°C',
        weatherLook(f.current.code).$1,
        if (f.current.feelsLikeC != null)
          'feels like ${f.current.feelsLikeC!.round()}°C',
      ].join(', '),
      'forecast next days': [
        for (final day in f.days)
          '${shortDate(day.date)}: ${weatherLook(day.code).$1}, '
              '${day.minC?.round() ?? '?'}-${day.maxC?.round() ?? '?'}°C, '
              'rain ${day.rainMm?.toStringAsFixed(0) ?? '?'} mm'
              '${day.rainChance == null ? '' : ' (${day.rainChance}% chance)'}',
      ].join('; '),
    },
    if (r?.asOf != null) ...{
      'rain last 7 days (NASA, to ${shortDate(r!.asOf!)})': r.rain7dMm == null
          ? 'not known'
          : '${r.rain7dMm!.round()} mm, ${compared(r.rainVsPast, 'less than usual', 'more than usual')}',
      'soil wetness deep down (NASA)': compared(
        r.wetnessVsPast,
        'drier than usual',
        'wetter than usual',
      ),
    },
    if (et0?.totalMm != null)
      'water a grass field lost in those 7 days (FAO-56)':
          '${et0!.totalMm!.round()} mm',
    if (green?.ndviMean != null)
      'green cover from space (NASA HLS NDVI, 0 bare to 1 dense)':
          '${green!.ndviMean!.toStringAsFixed(2)} on ${shortDate(green.date)}',
    'last watered': log.isEmpty
        ? 'not logged'
        : '${now.difference(log.first).inDays} days ago',
    'tasks to do today': todo.isEmpty ? 'none' : todo.join('; '),
    'crop advice': S.cropsUnknownTitle,
  };
  if (!kIsWeb) {
    facts.removeWhere((key, _) => key.startsWith('weather now') || key.startsWith('forecast next') || key.startsWith('rain last 7') || key.startsWith('soil wetness') || key.startsWith('tasks to do today') || key == 'last watered');
    final date = ref.read(simulationClockProvider);
    final state = ref.read(analysisProvider);
    final monthly = state is AnalysisReady ? state.analysis.climateSummary.months.where((m) => m.year == date.year && m.month == date.month).firstOrNull : null;
    facts['today'] = date.toIso8601String().substring(0,10);
    facts['mode'] = 'Historical simulation, not real time';
    if (ref.read(referenceChoiceProvider)) {
      final reference = ref.read(historicalReferenceProvider).value;
      final rows = reference?['months'] as List? ?? [];
      final selected = rows.where((m)=>m['year']==date.year && m['month']==date.month).firstOrNull as Map?;
      facts['historical reference source'] = 'Explicit archived Yangon point 16.85, 96.15, not measurements from this farm';
      facts['historical month temperature'] = 'Unknown in the offline reference';
      facts['historical month rainfall'] = selected?['rain_mm'] == null ? 'Unknown' : '${selected!['rain_mm']} mm for ${date.month}/${date.year}, archived Yangon reference only';
      return facts;
    }
    facts['historical month temperature'] = monthly?.tempMeanC == null ? 'unknown' : '${monthly!.tempMeanC} C, monthly mean for ${date.month}/${date.year}; not a daily reading';
    facts['historical month rainfall'] = monthly?.rainMm == null ? 'unknown' : '${monthly!.rainMm} mm total for ${date.month}/${date.year}; not a daily reading';
  }
  return facts;
}

class ChatState {
  const ChatState({this.messages = const [], this.sending = false, this.error});
  final List<ChatMessage> messages;
  final bool sending;
  final String? error;
}

/// The conversation (last 30 messages kept on the phone).
class ChatNotifier extends Notifier<ChatState> {
  static const _key = 'chat_history';

  @override
  ChatState build() {
    final raw = ref.read(prefsProvider)?.getString(_key);
    if (raw == null) return const ChatState();
    try {
      return ChatState(
        messages: [
          for (final m in jsonDecode(raw) as List)
            ChatMessage(
              fromUser: (m as Map)['u'] == true,
              text: m['t'] as String,
            ),
        ],
      );
    } catch (_) {
      return const ChatState();
    }
  }

  void _save() => ref
      .read(prefsProvider)
      ?.setString(
        _key,
        jsonEncode([
          for (final m in state.messages.skip(
            state.messages.length > 30 ? state.messages.length - 30 : 0,
          ))
            {'u': m.fromUser, 't': m.text},
        ]),
      );

  Future<void> send(String text, Map<String, String> farm) async {
    final q = text.trim();
    if (q.isEmpty || state.sending) return;
    final previous = state.messages;
    final msgs = [...previous.skip(previous.length > 28 ? previous.length - 28 : 0), ChatMessage(fromUser: true, text: q)];
    state = ChatState(messages: msgs, sending: true);
    _save();
    try {
      final answer = await ref.read(chatClientProvider).ask(msgs, farm);
      if (!ref.mounted) return;
      state = ChatState(
        messages: [
          ...msgs,
          ChatMessage(fromUser: false, text: answer),
        ],
      );
      _save();
      ref.read(cloudSyncProvider)?.logEvent('chat_answer');
    } on ChatException catch (e) {
      if (!ref.mounted) return;
      state = ChatState(
        messages: msgs,
        error: switch (e.code) {
          'not_configured' => S.chatNotSetUp,
          'ai_busy' => S.chatBusy,
          'unreachable' => backendMessage(e.code),
          'backend_route_missing' || 'backend_access_denied' || 'backend_unavailable' || 'backend_invalid_response' || 'ai_key_rejected' => backendMessage(e.code),
          _ => S.chatFailed,
        },
      );
    }
  }

  Future<void> retry(Map<String, String> farm) async {
    if (state.sending || state.error == null || state.messages.isEmpty) return;
    final last = state.messages.last;
    if (!last.fromUser) return;
    state = ChatState(messages: state.messages.take(state.messages.length - 1).toList());
    await send(last.text, farm);
  }

  void clear() {
    state = const ChatState();
    ref.read(prefsProvider)?.remove(_key);
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
