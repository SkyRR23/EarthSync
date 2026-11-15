import 'dart:convert';
import 'package:flutter/services.dart';

Future<Map<String, dynamic>>? _corpus;

/// Bounded local reference lookup and authored checklists, never labelled as
/// Groq output, a diagnosis or a source-verified model answer.
Future<String> offlineFarmReply(String question, Map<String, String> farm) async {
  final data = await (_corpus ??= rootBundle.loadString('assets/fixtures/offline_help.json')
      .then((raw) => jsonDecode(raw) as Map<String, dynamic>));
  final q = question.toLowerCase();
  final text = '$q ${farm['crops grown'] ?? ''}'.toLowerCase();
  final output = <String>['OFFLINE GUIDE · not an AI-generated answer'];
  if (farm['mode'] != null) output.add('Simulation day: ${farm['today']}. Historical context, not live conditions.');
  bool contains(List<String> words) => words.any(q.contains);
  final pests = contains(['(pests)', 'pest', 'insect', 'crawling', 'ပိုး']);
  final water = contains(['(water)', 'water', 'rain', 'wind', 'ရေ']);
  final soil = contains(['(soil)', 'soil', 'crack', 'compaction', 'မြေ']);
  final stress = contains(['(growth)', 'yellow', 'strip', 'leaf', 'leaves', 'အရွက်']);
  final aboutField = contains(['know about my field', 'my farm details']);
  final rice = text.contains('rice') || text.contains('စပါး');
  final mung = text.contains('mung') || text.contains('green gram');
  output.add('General checklist (app guidance):');
  if (aboutField && farm.isNotEmpty) {
    for (final key in ['crops grown', 'soil type', 'watering', 'historical reference source', 'historical month rainfall']) {
      if (farm[key] != null) output.add('• $key: ${farm[key]}');
    }
  } else if (pests) {
    output.add('• Compare affected and unaffected plants; look at both sides of leaves.');
    output.add('• Record the crop stage and photograph the insects and damage. Ask a local agricultural adviser to identify them before choosing treatment.');
    output.add('• This guide cannot identify an insect or choose a pesticide from a note.');
  } else if (soil) {
    output.add('• Compare wet and dry areas and note crusts, cracks or standing water. A hand test does not establish soil chemistry.');
    output.add('• Use Soil properties for modelled pH, clay and sand layers. They need an internet connection and are reference maps, not current soil readings.');
  } else if (water) {
    output.add('• Open Weather for dated historical rain, then check soil moisture and drainage in your simulation. Rain at the reference point is not a measurement of your field.');
    output.add('• Record whether the soil is wet or watering was done in Suggested checks. This guide cannot determine an irrigation amount or today’s wind.');
  } else if (stress) {
    output.add('• Compare affected and unaffected plants and older versus newer leaves. Record the crop stage and recent management.');
    output.add('• Leaf colour alone cannot identify the cause. Keep a dated note and seek local advice if damage spreads.');
  } else if (rice || mung || contains(['grow', 'plant', 'crop', 'စိုက်'])) {
    output.add(rice
        ? '• For rice, start by choosing a locally suitable variety and deciding whether you will direct-seed or transplant.'
        : mung ? '• For mung beans, start with a locally suitable variety and check seed quality and field drainage.'
        : '• Start with a locally suitable variety, good seed and a planting method suited to your water supply.');
    output.add('• Check the planting window and field preparation with a local agricultural adviser. Monitor weeds, insects and plant growth and keep dated notes.');
    output.add('• Open Plan my next crops to compare three-season options and see “consider this instead, because…” reasons. Exact spacing, fertiliser and planting dates are not established by this offline guide.');
  } else {
    output.add('• This offline guide covers crop planning, pests, water, soil and saved field details. Try one of those topics, or turn on Online AI for an open-ended question.');
  }

  final crops = data['crops'] as List;
  final cropIds = <String>{};
  for (final crop in crops) {
    final aliases = [crop['scientific_name'], ...crop['aliases'] as List];
    if (aliases.any((a) => (a as String).length >= 4 && RegExp('(?<![a-z])${RegExp.escape(a.toLowerCase())}(?![a-z])').hasMatch(text))) cropIds.add(crop['id'] as String);
  }
  if (rice) cropIds.add('ecocrop.1574@1');
  if (mung) cropIds.add('ecocrop.2150@1');
  final selected = <Map>[];
  for (final raw in data['claims'] as List) {
    final claim = raw as Map;
    final id = claim['id'] as String;
    final cropMatches = cropIds.contains(claim['crop_id']);
    if ((soil && id == 'health.soil.surface') ||
        (stress && cropMatches && id == 'health.maize.yellowing') ||
        (!pests && cropMatches && claim['parameter'] == 'ecological_temperature')) {
      selected.add(claim);
    }
    if (selected.length == 2) break;
  }
  if (selected.isNotEmpty) {
    output.add('\nMatched saved references (separate from the checklist):');
    for (final claim in selected) {
      final source = (data['sources'] as Map)[claim['source_id']] as Map;
      if (claim['claim'] != null) {
        output.add('${claim['claim']}');
      } else {
        final range = (claim['value'] as Map?)?['optimal'] as Map?;
        if (range != null) output.add('Global species reference: ${range['min']}–${range['max']} °C optimal temperature band. It is not a local planting threshold or a daily forecast.');
      }
      if (claim['follow_up'] is List) {
        for (final step in claim['follow_up'] as List) output.add('• $step');
      }
      for (final limit in (claim['limitations'] as List? ?? []).take(2)) output.add('Limit: $limit');
      output.add('${source['title']}\n${source['url']}');
    }
  } else {
    output.add('\nNo matching saved reference was found. The checklist above is general app guidance, not a retrieved diagnosis or verified field recommendation.');
  }
  return output.join('\n');
}
