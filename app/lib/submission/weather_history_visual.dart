import 'package:flutter/material.dart';

/// Weather-card presentation of dated values; no synthetic sky conditions.
class WeatherHistoryVisual extends StatelessWidget {
  const WeatherHistoryVisual({super.key, required this.date, required this.source,
    this.temperature, this.rain, this.wetness, this.rainIsDaily = false,
    this.days = const [], this.compact = false, this.onOpen});
  final DateTime date;
  final String source;
  final double? temperature, rain, wetness;
  final bool rainIsDaily, compact;
  final List<Map<String,dynamic>> days;
  final VoidCallback? onOpen;
  String get _date => '${date.day}/${date.month}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final value = temperature != null ? '${temperature!.round()}°C' : rain != null ? '${rain!.toStringAsFixed(1)} mm' : '—';
    final metric = temperature != null ? 'Monthly mean temperature' : rain != null ? (rainIsDaily ? 'Rainfall on this archived day' : 'Rainfall for this historical month') : 'No value loaded for this date';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: EdgeInsets.all(compact ? 16 : 24),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(begin: Alignment.topLeft,end: Alignment.bottomRight,colors:[Color(0xFF235B83),Color(0xFF367C94)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(source,style:TextStyle(color:Colors.white,fontSize:compact ? 18 : 24,fontWeight:FontWeight.w600))),const Icon(Icons.history,color:Colors.white)]),
          const SizedBox(height:6),
          Text('$_date · Historical simulation',style:const TextStyle(color:Colors.white,fontSize:15)),
          const SizedBox(height:18),
          Row(children:[Icon(temperature != null ? Icons.thermostat : Icons.water_drop_outlined,size:compact ? 38 : 62,color:Colors.white),const SizedBox(width:16),Expanded(child:FittedBox(fit:BoxFit.scaleDown,alignment:Alignment.centerRight,child:Text(value,style:TextStyle(color:Colors.white,fontSize:compact ? 42 : 68,fontWeight:FontWeight.w300))))]),
          Text(metric,style:const TextStyle(color:Colors.white,fontSize:15)),
          if (compact && onOpen != null) Align(alignment:Alignment.centerRight,child:TextButton(onPressed:onOpen,style:TextButton.styleFrom(foregroundColor:Colors.white),child:const Text('View weather history →'))),
        ]),
      ),
      if (!compact) ...[
        const SizedBox(height:16),
        if(days.isNotEmpty) ...[
          Text('Archived daily rainfall · last 7 days',style:Theme.of(context).textTheme.titleMedium),
          const SizedBox(height:8),
          SizedBox(height:126,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:days.length,separatorBuilder:(_,_)=>const SizedBox(width:8),itemBuilder:(context,index){
            final item=days[index]; final day=item['date'] as DateTime; final amount=item['rain'] as num?;
            return Container(width:88,padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:index==days.length-1 ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface,borderRadius:BorderRadius.circular(18)),child:Column(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('${day.day}/${day.month}',style:const TextStyle(fontWeight:FontWeight.w600)),const Icon(Icons.water_drop_outlined),Text(amount==null ? 'Unknown' : '${amount.toStringAsFixed(1)} mm',textAlign:TextAlign.center)]));
          })),
          const SizedBox(height:16),
        ],
        Wrap(spacing:12,runSpacing:12,children:[
          _metric(context,Icons.thermostat,'Monthly temperature',temperature==null?'Not in this data':'${temperature!.toStringAsFixed(1)} °C'),
          _metric(context,Icons.water_drop_outlined,rainIsDaily?'Archived day rainfall':'Historical month rain',rain==null?'Unknown':'${rain!.toStringAsFixed(1)} mm'),
          if(wetness!=null) _metric(context,Icons.layers_outlined,'Model wetness index',wetness!.toStringAsFixed(3)),
        ]),
        const SizedBox(height:12),
        const Text('Historical values, not live weather. The model wetness index is regional context, not a soil-health score. This archive does not include hourly weather or wind.'),
      ],
    ]);
  }
  Widget _metric(BuildContext context,IconData icon,String title,String value)=>Container(width:150,padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:Theme.of(context).colorScheme.surface,borderRadius:BorderRadius.circular(18)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon),const SizedBox(height:8),Text(title,style:Theme.of(context).textTheme.bodySmall),const SizedBox(height:6),Text(value,style:Theme.of(context).textTheme.titleMedium)]));
}
