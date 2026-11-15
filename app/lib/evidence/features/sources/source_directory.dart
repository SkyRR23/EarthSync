import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../design/tokens.dart';
import '../../state/platform_provider.dart';

final datasetDirectoryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
      final client = ref.watch(platformFarmClientProvider);
      if (client == null) return null;
      final result = await client.transport.request(
        'GET',
        '/api/platform/v1/datasets',
        expectedStatus: 200,
      );
      final data = Map<String, dynamic>.from(result as Map);
      if (data['schema_version'] != 'earthsync.dataset-registry.v1' ||
          data['datasets'] is! List) {
        throw const FormatException('Dataset registry contract mismatch');
      }
      return data;
    });

class SourceDirectory extends ConsumerWidget {
  const SourceDirectory({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(datasetDirectoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sources & Evidence',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const Text(
          'Know where each result comes from. Source availability and scientific applicability are different questions.',
        ),
        const SizedBox(height: FsSpace.md),
        for (final source in const [
          (
            'NASA POWER',
            'Historical modeled rainfall and temperature. The selected dates, LST calendar and native grid remain attached to each retrieval.',
            'https://power.larc.nasa.gov/',
          ),
          (
            'ISRIC SoilGrids',
            'Modeled soil properties, such as pH in water. Check depth, native spatial resolution, nodata and retrieval time. These are not laboratory measurements or crop suitability ratings.',
            'https://soilgrids.org/',
          ),
          (
            'NASA HLS / Earthdata',
            'Satellite acquisitions and QA-masked NDVI. Cloud masks, native resolution and original acquisition dates remain visible. Greenness is not a diagnosis.',
            'https://www.earthdata.nasa.gov/data/projects/hls',
          ),
          (
            'Weather observations, forecasts & warnings',
            'Only the source-specific current/forecast cards establish coverage. NASA historical climate is not an official warning service.',
            'https://www.weather.gov/',
          ),
          (
            'Crop reference knowledge',
            'Published crop characteristics support exploration. All 60 candidate executable suitability rules remain blocked.',
            'https://www.fao.org/land-water/land/land-governance/land-resources-planning-toolbox/',
          ),
        ])
          Card(
            child: ExpansionTile(
              title: Text(source.$1),
              subtitle: const Text('About this source'),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              childrenPadding: const EdgeInsets.all(FsSpace.md),
              children: [
                Text(source.$2),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      final opened = await launchUrl(
                        Uri.parse(source.$3),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!opened && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'The source link could not be opened.',
                            ),
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'The source link is unavailable on this platform.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open original source'),
                ),
              ],
            ),
          ),
        ExpansionTile(
          title: const Text('Server dataset registry'),
          subtitle: const Text(
            'Installation status, licenses, versions and cache restrictions',
          ),
          children: [
            if (registry.isLoading) const LinearProgressIndicator(),
            if (registry.hasError || registry.value == null)
              const Text(
                'The server registry is unavailable. Local farm management remains available. Dataset installation has not been assumed.',
              ),
            for (final row in registry.value?['datasets'] as List? ?? [])
              ListTile(
                title: Text('${row['name']} · ${row['version']}'),
                subtitle: Text(
                  '${row['processing_status']} · ${row['validation_status']}\n${row['license']}\n${row['cache_policy']}',
                ),
              ),
          ],
        ),
      ],
    );
  }
}
