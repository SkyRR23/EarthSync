import '../features/home/home_shell.dart';
import 'historical_reference.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../src/rust/api/bridge.dart' as rust;
import '../data/engine/rust_engine.dart';
import '../state/providers.dart';
import 'simulation_clock.dart';
import 'simulation_observations.dart';

final simulationAdviceProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final date = ref.watch(simulationClockProvider);
  final notes = ref.watch(notesProvider);
  final checks = ref.watch(simulationChecksProvider);
  final contextKey = ref.watch(simulationObservationKeyProvider);
  final state = ref.watch(analysisProvider);
  final month = state is AnalysisReady ? state.analysis.climateSummary.months.where((m) => m.year == date.year && m.month == date.month).firstOrNull : null;
  final usingReference = ref.watch(referenceChoiceProvider);
  final reference = usingReference ? await ref.watch(historicalReferenceProvider.future) : null;
  String key(DateTime d) => '${d.year.toString().padLeft(4,'0')}${d.month.toString().padLeft(2,'0')}${d.day.toString().padLeft(2,'0')}';
  final daily = reference?['daily'] as Map?;
  final reading = daily?[key(date)] as Map?;
  final rains = [for(var i=0;i<7;i++) (daily?[key(date.subtract(Duration(days:i)))] as Map?)?['rain_mm'] as num?];
  final rain7 = usingReference && rains.every((v)=>v!=null) ? rains.fold<double>(0,(total,v)=>total+v!.toDouble()) : null;
  final request = {'schema_version':'earthsync.simulation.v1', 'operation':'tasks', 'simulation_date':date.toIso8601String().substring(0,10),
    'month_mean_temp_c':usingReference ? null : month?.tempMeanC, 'month_rain_mm':month?.rainMm, 'heat_trigger_c':30.0,
    'watered_today':simulationChecked(checks, contextKey, 'watered'),
    'soil_wet_today':simulationChecked(checks, contextKey, 'soil_wet'),
    'pest_report':notes.any((n) => n.simulated && n.kind.name == 'pests' && n.createdAt.isBefore(date.add(const Duration(days:1))) && !n.createdAt.isBefore(date.subtract(const Duration(days:6)))),
    'checked_ids':[for(final id in ['reference','reference_soil','water','pests','wind','record']) if(simulationChecked(checks, contextKey, id)) id],
    'wind_kmh':null, 'reference_rain7_mm':rain7, 'reference_root_wetness':reading?['root_wetness'], 'context_source':usingReference ? 'Archived NASA POWER Yangon point 16.85, 96.15; reference only, not the saved field' : 'Loaded historical field context',
  };
  await RustEngine.init();
  return jsonDecode(await rust.analyzeIntegrationJson(requestJson:jsonEncode(request))) as Map<String,dynamic>;
});

class SimulationAdvicePanel extends ConsumerWidget {
  const SimulationAdvicePanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contextKey = ref.watch(simulationObservationKeyProvider);
    void mark(String id, bool done) => ref.read(simulationChecksProvider.notifier).mark(contextKey, id, done);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SimulationBanner(compact:true),
      const Text('Suggested checks for this simulation day', style: TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
      if(ref.watch(referenceChoiceProvider)) const Text('Using the explicitly selected archived Yangon reference; no measurement from your saved field is assumed.'),
      const Text('These checks use historical context and your simulation observations. Tap a check when you have done it.'),
      ref.watch(simulationAdviceProvider).when(
        loading:()=>const LinearProgressIndicator(),
        error:(error,_)=>Text('The simulation engine could not produce checks: $error'),
        data:(result)=>Column(children:[for(final task in result['tasks'] as List? ?? []) Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Icon(task['done']==true ? Icons.check_circle : switch(task['id']) {
              'water' => Icons.water_drop_outlined,
              'pests' => Icons.pest_control,
              'reference' => Icons.umbrella_outlined,
              'reference_soil' => Icons.layers_outlined,
              _ => Icons.fact_check_outlined,
            }),
            const SizedBox(width:8),
            Expanded(child:Text('${task['title']}',style:const TextStyle(fontWeight:FontWeight.bold))),
          ]),
          ExpansionTile(tilePadding:EdgeInsets.zero,title:const Text('Why this check?'),children:[Text('${task['reason']}')]),
          if(task['id']=='water' && task['done']!=true) Wrap(spacing:8,children:[
            TextButton(onPressed:()=>mark('watered',true),child:const Text('I watered on this simulation day')),
            TextButton(onPressed:()=>mark('soil_wet',true),child:const Text('I checked: soil is wet')),
          ]),
          if(task['id']=='record' || task['id']=='pests') TextButton(onPressed:(){ final tabs = HomeTabs.of(context); if(tabs != null) { tabs.go(3); } else { context.go('/home?tab=3'); } },child:const Text('Open farm records')),
          TextButton.icon(onPressed:(){
            final done = task['done']==true;
            mark(task['id'] as String,!done);
            if(done && task['id']=='water') { mark('watered',false); mark('soil_wet',false); }
          },icon:Icon(task['done']==true ? Icons.undo : Icons.check),label:Text(task['done']==true ? 'Undo check' : 'Mark checked')),
        ])))]),
      ),
      const ExpansionTile(title:Text('Simulation assumptions'),children:[
        Padding(padding:EdgeInsets.all(12),child:Text('Hot-month trigger: 30 °C. Monthly averages are not daily conditions. Wind and pest-season forecasts stay unknown without dated data. Checks are saved locally for this field and simulation day, separately from real watering records.')),
      ]),
    ]);
  }
}
