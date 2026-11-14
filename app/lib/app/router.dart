import '../features/companion/companion_screen.dart';
import '../features/companion/crop_explorer.dart';
import '../features/companion/farm_photos.dart';
import '../features/field/platform_farm_screen.dart';
import '../features/dashboard/daily_climate_screen.dart';
import '../design/app_shell.dart';
import '../features/explore/explore_screen.dart';
import '../features/settings/settings_screen.dart';
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
import '../features/field/field_screen.dart';
import '../features/field/photos_screen.dart';
import '../features/field/assessment_screen.dart';
import '../features/assistant/integrated_assistant.dart';

GoRouter buildRouter() => GoRouter(
  routes: [
    ShellRoute(
      builder: (_, state, child) =>
          AppShell(path: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/daily-climate',
          builder: (_, s) => DailyClimateScreen(
            farmMode: s.uri.queryParameters['farm'] == '1',
          ),
        ),
        GoRoute(
          path: '/farm-evidence',
          builder: (_, _) => const FarmRequired(child: PlatformFarmScreen()),
        ),
        GoRoute(
          path: '/season',
          builder: (_, _) => const FarmRequired(child: CompanionScreen()),
        ),
        GoRoute(path: '/crops', builder: (_, _) => const CropExplorer()),
        GoRoute(
          path: '/farm-photos',
          builder: (_, _) => const FarmRequired(child: FarmPhotosScreen()),
        ),
        GoRoute(path: '/explore', builder: (_, _) => const ExploreScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(path: '/', builder: (_, _) => const HomeEntry()),
        GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
        GoRoute(
          path: '/field',
          builder: (_, _) => const FarmRequired(child: FieldScreen()),
        ),
        GoRoute(
          path: '/photos',
          builder: (_, _) => const FarmRequired(child: PhotosScreen()),
        ),
        GoRoute(
          path: '/assessment',
          builder: (_, _) => const FarmRequired(child: AssessmentScreen()),
        ),
        GoRoute(
          path: '/assistant',
          builder: (_, s) => IntegratedAssistantScreen(
            areaOnly: s.uri.queryParameters['area'] == '1',
          ),
        ),
        GoRoute(
          path: '/area',
          builder: (_, _) => const LocationScreen(areaOnly: true),
        ),
        GoRoute(
          path: '/location',
          builder: (_, s) => LocationScreen(
            editing: s.uri.queryParameters['edit'] == '1',
            newFarm: s.uri.queryParameters['new'] == '1',
          ),
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
    ),
  ],
);
