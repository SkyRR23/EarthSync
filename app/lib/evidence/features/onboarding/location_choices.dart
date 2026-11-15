import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/location/device_location.dart';
import '../../data/models/home_profile.dart';
import '../../state/home_provider.dart';

class LocationChoices extends ConsumerStatefulWidget {
  const LocationChoices({
    super.key,
    this.showSkip = true,
    this.areaLabel = 'Choose an Area',
  });
  final bool showSkip;
  final String areaLabel;
  @override
  ConsumerState<LocationChoices> createState() => _LocationChoicesState();
}

class _LocationChoicesState extends ConsumerState<LocationChoices> {
  bool _busy = false;
  String? _message;
  Future<void> _locate() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final point = await ref.read(deviceLocationProvider).locate();
      if (!mounted) return;
      await ref
          .read(homeProfileProvider.notifier)
          .setArea(
            ApproximateArea(
              point: point,
              label: 'Near your location',
              source: AreaSource.device,
            ),
          );
      if (mounted) context.go('/dashboard');
    } on LocationFailure catch (e) {
      try {
        await ref.read(homeProfileProvider.notifier).skip(e.reason);
      } catch (_) {}
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not save your choice on this device. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    setState(() => _busy = true);
    try {
      await ref.read(homeProfileProvider.notifier).skip();
      if (mounted) context.go('/dashboard');
    } catch (_) {
      // Storage must not prevent entry to the dashboard.
      if (mounted) context.go('/dashboard');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(_message!, semanticsLabel: _message),
        ),
      FilledButton.icon(
        onPressed: _busy ? null : _locate,
        icon: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location),
        label: Text(_busy ? 'Finding your area…' : 'Use My Location'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => context.push('/area'),
        icon: const Icon(Icons.public),
        label: Text(widget.areaLabel),
      ),
      if (widget.showSkip)
        TextButton(
          onPressed: _busy ? null : _skip,
          child: const Text('Skip for Now'),
        ),
    ],
  );
}
