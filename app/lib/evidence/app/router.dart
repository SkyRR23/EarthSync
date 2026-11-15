import 'package:flutter/foundation.dart';
import '../../submission/simulation_advice.dart';
import 'package:go_router/go_router.dart';
import '../features/historical/historical_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/tasks/notifications_screen.dart';
import '../features/companion/local_records_screen.dart';
import '../features/companion/rotation_workspace.dart';
import '../features/companion/companion_screen.dart';
import '../features/companion/crop_explorer.dart';
import '../features/companion/farm_photos.dart';
import '../features/settings/local_data_screen.dart';
import '../features/field/platform_farm_screen.dart';
import '../features/field/field_screen.dart';
import '../features/field/photos_screen.dart';
import '../features/field/assessment_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dashboard/daily_climate_screen.dart';
import '../features/assistant/integrated_assistant.dart';
import '../features/map/ndvi_panel.dart';
import '../features/realtime/realtime_panel.dart';
import '../features/onboarding/farm_required.dart';

/// Detail tools share the primary app's router and selected farm.
List<RouteBase> buildEvidenceRoutes() => [
  GoRoute(path: '/local-data', builder: (_, _) => const LocalDataScreen()),
  GoRoute(
    path: '/local-records',
    builder: (_, s) => FarmRequired(
      child: LocalRecordsScreen(
        initialKind: s.uri.queryParameters['kind'] ?? 'observation',
      ),
    ),
  ),
  GoRoute(
    path: '/tasks',
    builder: (_, s) =>
        FarmRequired(child: TasksScreen(taskId: s.uri.queryParameters['task'], advice: kIsWeb ? null : const SimulationAdvicePanel())),
  ),
  GoRoute(
    path: '/notifications',
    builder: (_, _) => const NotificationsScreen(),
  ),
  GoRoute(
    path: '/historical',
    builder: (_, _) => const FarmRequired(child: HistoricalScreen()),
  ),
  GoRoute(path: '/ndvi', builder: (_, _) => const NdviScreen()),
  GoRoute(path: '/crop-intelligence', builder: (_, _) => const CropExplorer()),
  GoRoute(
    path: '/image-analysis',
    builder: (_, _) => const FarmRequired(child: FarmPhotosScreen()),
  ),
  GoRoute(
    path: '/lab-reports',
    builder: (_, _) =>
        const FarmRequired(child: FarmPhotosScreen(initialKind: 'lab')),
  ),
  GoRoute(
    path: '/farm-photos',
    builder: (_, _) => const FarmRequired(child: FarmPhotosScreen()),
  ),
  GoRoute(
    path: '/realtime',
    builder: (_, s) =>
        RealtimeScreen(initialField: s.uri.queryParameters['field'] == '1'),
  ),
  GoRoute(
    path: '/daily-climate',
    builder: (_, s) =>
        DailyClimateScreen(farmMode: s.uri.queryParameters['farm'] == '1'),
  ),
  GoRoute(
    path: '/farm-evidence',
    builder: (_, _) => const FarmRequired(child: PlatformFarmScreen()),
  ),
  GoRoute(
    path: '/rotations',
    builder: (_, _) => const FarmRequired(child: RotationWorkspace()),
  ),
  GoRoute(
    path: '/season',
    builder: (_, _) => const FarmRequired(child: CompanionScreen()),
  ),
  GoRoute(
    path: '/field-evidence',
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
    path: '/climate-overview',
    builder: (_, _) => const DashboardScreen(),
  ),
  GoRoute(path: '/dashboard', redirect: (_, _) => '/home'),
  GoRoute(path: '/field', redirect: (_, _) => '/home?tab=2'),
  GoRoute(path: '/weather', redirect: (_, _) => '/home?tab=1'),
  GoRoute(path: '/settings', redirect: (_, _) => '/field-details'),
  GoRoute(path: '/area', redirect: (_, _) => '/location'),
  GoRoute(path: '/explore', redirect: (_, _) => '/historical'),
];
