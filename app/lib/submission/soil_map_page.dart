import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../design/components/page.dart';
import '../evidence/features/map/soil_first_map.dart';
import 'farm_bridge.dart';

class SoilMapPage extends ConsumerWidget {
  const SoilMapPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => FsPage(
    title: 'Soil & field map',
    children: [
      ref
          .watch(selectedFarmBridgeProvider)
          .when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text('Saved field could not open: $error'),
            data: (profile) => profile.farm == null
                ? TextButton(
                    onPressed: () => context.push('/location'),
                    child: const Text('Choose your field'),
                  )
                : SoilFirstMap(farm: profile.farm!),
          ),
      TextButton.icon(
        onPressed: () => context.push('/soil-test'),
        icon: const Icon(Icons.edit_note),
        label: const Text('Record a farmer soil check'),
      ),
      TextButton(
        onPressed: () => context.push('/local-records?kind=soil'),
        child: const Text('Saved soil checks & observations'),
      ),
      TextButton(
        onPressed: () => context.push('/sources'),
        child: const Text('About these sources'),
      ),
    ],
  );
}
