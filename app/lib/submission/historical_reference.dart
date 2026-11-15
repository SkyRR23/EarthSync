import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';

class ReferenceChoice extends Notifier<bool> {
  @override
  bool build() => ref.read(prefsProvider)?.getBool('simulation.use.yangon.reference') ?? false;
  void select(bool value) {
    state = value;
    ref.read(prefsProvider)?.setBool('simulation.use.yangon.reference',value);
  }
}
final referenceChoiceProvider = NotifierProvider<ReferenceChoice,bool>(ReferenceChoice.new);
final historicalReferenceProvider = FutureProvider<Map<String,dynamic>>((ref) async => jsonDecode(await rootBundle.loadString('assets/fixtures/yangon_historical_reference.json')) as Map<String,dynamic>);
