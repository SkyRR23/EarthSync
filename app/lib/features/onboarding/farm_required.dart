import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../state/home_provider.dart';

class FarmRequired extends ConsumerWidget {
  const FarmRequired({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(homeProfileProvider);
    if (profile.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (profile.value?.farm != null) return child;
    return Scaffold(
      appBar: AppBar(title: const Text('Farm confirmation needed')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Confirm your field point before opening the farm questionnaire. You can explore area data without a farm.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.push('/location'),
            child: const Text('Add My Farm'),
          ),
          TextButton(
            onPressed: () => context.go('/dashboard'),
            child: const Text('Go to Dashboard'),
          ),
        ],
      ),
    );
  }
}
