import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/ui_copy.dart';
import '../state/home_provider.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.path});
  final Widget child;
  final String path;
  static const features = [
    ('Real-Time EarthSync', '/realtime', Icons.update),
    ('Satellite NDVI Map', '/ndvi', Icons.layers_outlined),
    ('Farm Map', '/location', Icons.map_outlined),
    ('Crops', '/crops', Icons.spa_outlined),
    ('Crop Intelligence', '/crop-intelligence', Icons.menu_book_outlined),
    ('Photos / Image Analysis', '/image-analysis', Icons.photo_camera_outlined),
    ('Laboratory Reports', '/lab-reports', Icons.science_outlined),
    ('Farmer Journal', '/season', Icons.history),
    ('Rotation Comparison', '/rotations', Icons.compare_arrows),
  ];
  static const destinations = [
    ('home', '/dashboard', Icons.grid_view_outlined),
    ('farm', '/field', Icons.grass_outlined),
    ('explore', '/explore', Icons.public_outlined),
    ('assistant', '/assistant', Icons.chat_bubble_outline),
    ('settings', '/settings', Icons.tune_outlined),
  ];
  int get selected => path == '/settings'
      ? 4
      : path == '/assistant'
      ? 3
      : ['/explore', '/area', '/crops'].contains(path)
      ? 2
      : [
              '/field',
              '/season',
              '/rotations',
              '/farm-photos',
              '/farm-evidence',
              '/photos',
              '/assessment',
              '/location',
              '/review',
              '/results',
            ].contains(path) ||
            path.startsWith('/question/') ||
            path.startsWith('/scenario/')
      ? 1
      : 0;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (path == '/' &&
        ref.watch(homeProfileProvider).value?.onboarded != true) {
      return child;
    }
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        return Scaffold(
          appBar: wide
              ? null
              : AppBar(title: const Text('EarthSync menu'), toolbarHeight: 44),
          drawer: wide
              ? null
              : Drawer(
                  child: SafeArea(
                    child: ListView(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'EarthSync',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        for (final feature in features)
                          ListTile(
                            leading: Icon(feature.$3),
                            title: Text(feature.$1),
                            onTap: () {
                              Navigator.of(context).pop();
                              context.go(feature.$2);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
          body: Row(
            // The nested Navigator blocks semantics painted before it. Paint
            // the rail after the route while keeping it on the left.
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: Semantics(
                  sortKey: const OrdinalSortKey(1),
                  child: FocusTraversalGroup(child: child),
                ),
              ),
              if (wide)
                Container(
                  width: 224,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      right: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    sortKey: const OrdinalSortKey(0),
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: SafeArea(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
                              child: Row(
                                children: [
                                  Icon(Icons.eco, size: 28),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'EarthSync',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (final (i, d) in destinations.indexed)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  selected: selected == i,
                                  selectedTileColor: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  leading: Icon(d.$3),
                                  title: Text(UiCopy.text(context, d.$1)),
                                  onTap: () => context.go(d.$2),
                                ),
                              ),
                            const Divider(),
                            for (final feature in features)
                              ListTile(
                                dense: true,
                                leading: Icon(feature.$3),
                                title: Text(feature.$1),
                                selected: path == feature.$2,
                                onTap: () => context.go(feature.$2),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                48,
                                20,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.public, size: 24),
                                  const SizedBox(height: 12),
                                  Text(
                                    UiCopy.text(context, 'evidenceFirst'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 16),
                                  TextButton.icon(
                                    onPressed: () => context.push('/realtime'),
                                    icon: const Icon(Icons.update),
                                    label: const Text('Real-time EarthSync'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => context.push('/sources'),
                                    icon: const Icon(
                                      Icons.menu_book_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      UiCopy.text(context, 'sources'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: selected,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  onDestinationSelected: (i) => context.go(destinations[i].$2),
                  destinations: [
                    for (final d in destinations)
                      NavigationDestination(
                        icon: Icon(d.$3),
                        label: UiCopy.text(context, d.$1),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
