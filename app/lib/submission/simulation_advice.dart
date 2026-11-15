import '../features/home/home_shell.dart';
import 'historical_reference.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../src/rust/api/bridge.dart' as rust;
import '../data/engine/rust_engine.dart';
import '../state/providers.dart';
import '../state/today.dart';
import 'simulation_clock.dart';

final simulationAdviceProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final date = ref.watch(simulationClockProvider);
  final notes = ref.watch(notesProvider);
  final marks = ref.watch(taskMarksProvider);
  final water = ref.watch(waterLogProvider);
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
    'watered_today':water.any((d) => dayKey(d) == dayKey(date)), 'soil_wet_today':marks['water_ok'] == dayKey(date),
    'pest_report':notes.any((n) => n.kind.name == 'pests' && !n.createdAt.isAfter(date.add(const Duration(days:1))) && date.difference(n.createdAt).inDays >= 0 && date.difference(n.createdAt).inDays < 7),
    'wind_kmh':null, 'reference_rain7_mm':rain7, 'reference_root_wetness':reading?['root_wetness'], 'context_source':usingReference ? 'Archived NASA POWER Yangon point 16.85, 96.15; reference only, not the saved field' : 'Loaded historical field context',
  };
  await RustEngine.init();
  return jsonDecode(await rust.analyzeIntegrationJson(requestJson:jsonEncode(request))) as Map<String,dynamic>;
});

class SimulationAdvicePanel extends ConsumerWidget {
  const SimulationAdvicePanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(simulationClockProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SimulationBanner(),
      const Text('Suggested checks for this simulation day', style: TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
      if(ref.watch(referenceChoiceProvider)) const Text('Using the explicitly selected archived Yangon reference; no measurement from your saved field is assumed.'),
      const Text('Simulation assumptions: hot-month trigger 30 °C. Monthly averages are not daily conditions. Wind and pest-season forecasts remain unknown without dated data.'),
      ref.watch(simulationAdviceProvider).when(
        loading:()=>const LinearProgressIndicator(),
        error:(error,_)=>Text('The simulation engine could not produce checks: $error'),
        data:(result)=>Column(children:[for(final task in result['tasks'] as List? ?? []) Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text('${task['title']}',style:const TextStyle(fontWeight:FontWeight.bold)), Text('${task['reason']}'),
          if(task['id']=='water' && task['done']!=true) Wrap(spacing:8,children:[
            TextButton(onPressed:()=>ref.read(waterLogProvider.notifier).logToday(date),child:const Text('I watered on this simulation day')),
            TextButton(onPressed:()=>ref.read(taskMarksProvider.notifier).mark('water_ok',dayKey(date)),child:const Text('I checked: soil is wet')),
          ]),
          if(task['id']=='record' || task['id']=='pests') TextButton(onPressed:(){ final tabs = HomeTabs.of(context); if(tabs != null) { tabs.go(3); } else { context.go('/home?tab=3'); } },child:const Text('Open farm records')),
        ]))))]),
      ),
    ]);
  }
}
