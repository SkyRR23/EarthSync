import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import '../features/home/farmer_start.dart';
import '../submission/soil_reference_page.dart';
import '../evidence/app/router.dart';
import '../submission/science_hub.dart';
import '../submission/soil_map_page.dart';
import '../submission/rotation_plans_page.dart';
import '../submission/next_season_page.dart';

import '../features/chat/chat_screen.dart';
import '../features/farm/mark_farm_screen.dart';
import '../features/home/climate_history.dart';
import '../features/home/field_tab.dart';
import '../features/home/home_shell.dart';
import '../features/location/location_screen.dart';
import '../features/map/map_screen.dart';
import '../features/onboarding/sign_in_screen.dart';
import '../features/onboarding/setup_flow.dart';
import '../features/questionnaire/question_screen.dart';
import '../features/results/scenario_detail_screen.dart';
import '../features/privacy/your_data_screen.dart';
import '../features/soil/soil_test_screen.dart';
import '../features/sources/sources_screen.dart';

/// Setup (first run only, team design): / welcome -> /setup/1..7 (location,
/// farm, crops, water, season, alerts, sign in) -> /home.
/// After setup /home keeps the team tabs and adds persistent local Tasks.
/// /crops = "Check my crops"; /field-details = answers and settings;
/// /climate = NASA months of the past year.
/// /farm marks the whole farm with 4 corner pins (from the Field tab).
GoRouter buildRouter({bool setupDone = false, bool introductionDone = true}) => GoRouter(
  initialLocation: !kIsWeb ? (introductionDone ? '/home' : '/intro') : setupDone ? '/home' : '/',
  routes: [
    GoRoute(path: '/intro', builder: (_, _) => const FarmerIntroduction()),
    ...buildEvidenceRoutes(),
    GoRoute(path: '/science', builder: (_, _) => const ScienceHub()),
    GoRoute(path: '/soil-map', builder: (_, _) => kIsWeb ? const SoilMapPage() : const SoilReferencePage()),
    GoRoute(
      path: '/rotation-plans',
      builder: (_, _) => const RotationPlansPage(),
    ),
    GoRoute(path: '/', builder: (_, _) => const SetupWelcome()),
    GoRoute(
      path: '/setup/:step',
      builder: (_, s) => SetupStepScreen(
        step: (int.tryParse(s.pathParameters['step'] ?? '') ?? 1).clamp(
          1,
          kSetupSteps,
        ),
      ),
    ),
    GoRoute(path: '/signin', builder: (_, _) => const SignInScreen()),
    GoRoute(
      path: '/location',
      builder: (_, s) => LocationScreen(
        editing: s.uri.queryParameters['edit'] == '1',
        setup: s.uri.queryParameters['setup'] == '1',
      ),
    ),
    GoRoute(
      path: '/question/:step',
      builder: (_, s) => QuestionScreen(
        step: (int.tryParse(s.pathParameters['step'] ?? '') ?? 1).clamp(
          1,
          kQuestionCount,
        ),
        editing: s.uri.queryParameters['edit'] == '1',
      ),
    ),
    GoRoute(
      path: '/home',
      builder: (_, s) => HomeShell(
        initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0,
      ),
    ),
    // Older links land on the new home.
    GoRoute(path: '/results', redirect: (_, _) => '/home'),
    GoRoute(path: '/review', redirect: (_, _) => '/home'),
    GoRoute(
      path: '/map',
      builder: (_, s) =>
          MapScreen(plantHealth: s.uri.queryParameters['layer'] == 'health'),
    ),
    GoRoute(path: '/farm', builder: (_, _) => const MarkFarmScreen()),
    GoRoute(path: '/chat', builder: (_, _) => const ChatScreen()),
    GoRoute(path: '/crops', builder: (_, _) => const NextSeasonPage()),
    GoRoute(
      path: '/field-details',
      builder: (_, _) => const FieldDetailsScreen(),
    ),
    GoRoute(
      path: '/climate',
      builder: (_, _) =>
          AnalysisGate(builder: (a, _) => ClimateHistoryPage(analysis: a)),
    ),
    GoRoute(path: '/soil-test', builder: (_, _) => const SoilTestScreen()),
    GoRoute(path: '/your-data', builder: (_, _) => const YourDataScreen()),
    GoRoute(
      path: '/scenario/:id',
      builder: (_, s) =>
          ScenarioDetailScreen(scenarioId: s.pathParameters['id']!),
    ),
    GoRoute(path: '/sources', builder: (_, _) => const SourcesScreen()),
  ],
);
