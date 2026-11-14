import 'package:go_router/go_router.dart';

import '../features/location/location_screen.dart';
import '../features/onboarding/home_entry.dart';
import '../features/onboarding/farm_required.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/questionnaire/question_screen.dart';
import '../features/questionnaire/review_screen.dart';
import '../features/results/results_screen.dart';
import '../features/results/scenario_detail_screen.dart';
import '../features/sources/sources_screen.dart';

GoRouter buildRouter() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeEntry()),
    GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
    GoRoute(
      path: '/area',
      builder: (_, _) => const LocationScreen(areaOnly: true),
    ),
    GoRoute(
      path: '/location',
      builder: (_, s) =>
          LocationScreen(editing: s.uri.queryParameters['edit'] == '1'),
    ),
    GoRoute(
      path: '/question/:step',
      builder: (_, s) => FarmRequired(
        child: QuestionScreen(
          step: (int.tryParse(s.pathParameters['step'] ?? '') ?? 1).clamp(
            1,
            kQuestionCount,
          ),
          editing: s.uri.queryParameters['edit'] == '1',
        ),
      ),
    ),
    GoRoute(
      path: '/review',
      builder: (_, _) => const FarmRequired(child: ReviewScreen()),
    ),
    GoRoute(path: '/results', builder: (_, _) => const ResultsScreen()),
    GoRoute(
      path: '/scenario/:id',
      builder: (_, s) =>
          ScenarioDetailScreen(scenarioId: s.pathParameters['id']!),
    ),
    GoRoute(path: '/sources', builder: (_, _) => const SourcesScreen()),
  ],
);
