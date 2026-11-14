import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/ui_copy.dart';
import '../state/home_provider.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.path});
  final Widget child;
  final String path;
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
          body: Row(
            children: [
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
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.public, size: 24),
                                const SizedBox(height: 12),
                                Text(
                                  UiCopy.text(context, 'evidenceFirst'),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 16),
                                TextButton.icon(
                                  onPressed: () => context.push('/sources'),
                                  icon: const Icon(
                                    Icons.menu_book_outlined,
                                    size: 18,
                                  ),
                                  label: Text(UiCopy.text(context, 'sources')),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(child: FocusTraversalGroup(child: child)),
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
