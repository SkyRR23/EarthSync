import 'package:flutter/material.dart';
import '../../design/tokens.dart';
import 'location_choices.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.eco_outlined, size: 64, color: FsColors.primary),
              const SizedBox(height: 24),
              Text(
                'Welcome to EarthSync',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Explore climate and satellite images for any area. Add your farm when you are ready.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Your location helps find an area. It does not mark your farm. You can continue without location permission.',
              ),
              const SizedBox(height: 24),
              const LocationChoices(),
              const SizedBox(height: 16),
              const Text(
                'Choices and confirmed farm points stay on this device. To show environmental data, selected coordinates go to our climate service and NASA POWER. Satellite views request NASA GIBS images. Opening the map requests OpenStreetMap tiles. No account or coordinate upload for other purposes.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Historical context, not a forecast or a guarantee. Missing data do not mean safe conditions.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
