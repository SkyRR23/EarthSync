import '../../app/ui_labels.dart';
import 'package:flutter/material.dart';
import '../../app/ui_copy.dart';
import '../../design/components/product.dart';
import 'location_choices.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    String tr(String k) => UiCopy.text(context, k);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Row(
                  children: [
                    Icon(Icons.eco, size: 32),
                    SizedBox(width: 10),
                    Text(
                      'EarthSync',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                ResponsivePair(
                  reverseOnNarrow: true,
                  first: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFF173D30),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: CustomPaint(
                      painter: LandContours(),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.spa_outlined,
                              color: Color(0xFFC9DFC2),
                              size: 42,
                            ),
                            const SizedBox(height: 32),
                            Text(
                              tr('tagline'),
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              tr('welcomeBody'),
                              style: const TextStyle(
                                color: Color(0xFFDBE8DD),
                                fontSize: 16,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 36),
                            Text(
                              tr('evidenceFirst'),
                              style: const TextStyle(color: Color(0xFFC9DFC2)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  second: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          tr('welcome'),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          UiLabels.exploreClimateAndSatelliteImagesForAnyArea,
                        ),
                        const SizedBox(height: 24),
                        const LocationChoices(),
                        const SizedBox(height: 20),
                        const Text(UiLabels.yourLocationHelpsFindAnAreaItDoes),
                        const SizedBox(height: 16),
                        ExpansionTile(
                          title: Text(tr('privacy')),
                          children: const [
                            Text(
                              UiLabels.choicesAndConfirmedFarmPointsStayOnThis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const SourceNote(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
