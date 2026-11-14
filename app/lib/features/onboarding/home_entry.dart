import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/home_provider.dart';
import '../dashboard/dashboard_screen.dart';
import 'welcome_screen.dart';

class HomeEntry extends ConsumerWidget {
  const HomeEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(homeProfileProvider)
      .when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => const WelcomeScreen(),
        data: (profile) =>
            profile.onboarded ? const DashboardScreen() : const WelcomeScreen(),
      );
}
