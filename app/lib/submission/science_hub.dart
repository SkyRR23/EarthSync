import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../design/components/page.dart';
import '../design/components/grouped.dart';

class ScienceHub extends StatelessWidget {
  const ScienceHub({super.key});
  @override
  Widget build(BuildContext context) => FsPage(
    title: 'Timeline & field evidence',
    children: [
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Explore your saved field history and dated source evidence. Historical scenarios are comparisons, not forecasts or crop prescriptions. Fresh source retrieval needs the connected EarthSync service.',
        ),
      ),
      FsGroupedSection(
        children: [
          for (final entry in const [
            (
              'Crop rotation decisions',
              '/rotation-plans',
              Icons.compare_arrows,
            ),
            ('Historical timeline demo', '/historical', Icons.history),
            ('Saved season & crop history', '/season', Icons.calendar_month),
            (
              'Soil properties & map layers',
              '/soil-map',
              Icons.layers_outlined,
            ),
            (
              'Field assessment & evidence',
              '/field-evidence',
              Icons.fact_check_outlined,
            ),
            (
              'Notes, soil checks & private photos',
              '/local-records',
              Icons.notes_outlined,
            ),
            ('Compare rotation strategies', '/rotations', Icons.compare_arrows),
            (
              'Crop reference search',
              '/crop-intelligence',
              Icons.menu_book_outlined,
            ),
            ('NASA vegetation pixels', '/ndvi', Icons.satellite_alt),
            (
              'Current environmental context',
              '/realtime?field=1',
              Icons.cloud_outlined,
            ),
            (
              'Laboratory reports & image evidence',
              '/image-analysis',
              Icons.science_outlined,
            ),
            ('Connect field data service', '/farm-evidence', Icons.link),
            ('Sources & data', '/sources', Icons.info_outline),
            ('Local export & privacy', '/local-data', Icons.download_outlined),
          ])
            FsListRow(
              leading: Icon(entry.$3),
              title: entry.$1,
              onTap: () => context.push(entry.$2),
            ),
        ],
      ),
    ],
  );
}
