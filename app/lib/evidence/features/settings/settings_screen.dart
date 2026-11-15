import '../../app/ui_labels.dart';
import '../../data/environment/platform_climate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/ui_copy.dart';
import '../../design/components/product.dart';
import '../../state/home_provider.dart';
import '../../state/preferences_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs =
        ref.watch(preferencesProvider).value ?? const AppPreferences();
    final profile = ref.watch(homeProfileProvider).value;
    String tr(String k) => UiCopy.text(context, k);
    Future<void> save({ThemeMode? theme, String? language}) async {
      try {
        await ref
            .read(preferencesProvider.notifier)
            .savePreferences(theme: theme, language: language);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(UiLabels.couldNotSavePreferencesTryAgain),
            ),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('settings'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (platformUrl.isNotEmpty)
                OutlinedButton(
                  onPressed: () => context.push('/farm-evidence'),
                  child: const Text('Persisted farm evidence'),
                ),
              PageHeader(title: tr('settings'), subtitle: tr('saved')),
              SectionCard(
                title: tr('appearance'),
                icon: Icons.palette_outlined,
                child: RadioGroup<ThemeMode>(
                  groupValue: prefs.theme,
                  onChanged: (value) => save(theme: value),
                  child: Column(
                    children: [
                      for (final mode in ThemeMode.values)
                        RadioListTile<ThemeMode>(
                          value: mode,
                          title: Text(tr(mode.name)),
                        ),
                    ],
                  ),
                ),
              ),
              SectionCard(
                title: tr('language'),
                icon: Icons.translate,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: prefs.language,
                      key: ValueKey(prefs.language),
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'my', child: Text('မြန်မာ')),
                      ],
                      onChanged: (v) => save(language: v),
                    ),
                    const SizedBox(height: 12),
                    Text(tr('languageNote')),
                  ],
                ),
              ),
              SectionCard(
                title: tr('farm'),
                icon: Icons.location_on_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((profile?.farms.length ?? 0) > 1)
                      DropdownButtonFormField<String>(
                        key: ValueKey(profile?.activeFarmId),
                        initialValue: profile?.activeFarmId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('farm')),
                        items: [
                          for (final f in profile!.farms)
                            DropdownMenuItem(
                              value: f.id,
                              child: Text(f.name ?? f.point.label),
                            ),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          try {
                            await ref
                                .read(homeProfileProvider.notifier)
                                .selectFarm(v);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not switch saved farm.'),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    TextButton(
                      onPressed: () => context.push('/location?new=1'),
                      child: Text(tr('farmAction')),
                    ),
                    if (profile?.farm case final farm?)
                      Text('${farm.name ?? tr('farm')} · ${farm.point.label}'),
                    TextButton(
                      onPressed: () => context.push('/location'),
                      child: Text(
                        profile?.farm == null
                            ? tr('farmAction')
                            : UiLabels.editMyFarm,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/area'),
                      child: Text(tr('areaAction')),
                    ),
                  ],
                ),
              ),
              EvidenceNotice(
                title: tr('privacy'),
                message: tr('privacyBody'),
                icon: Icons.shield_outlined,
              ),
              SectionCard(
                title: tr('about'),
                icon: Icons.eco_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('aboutBody')),
                    TextButton(
                      onPressed: () => context.push('/sources'),
                      child: Text(tr('sources')),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => context.push('/local-data'),
                child: const Text('Local data: export & privacy'),
              ),
              OutlinedButton(
                onPressed: () => context.push('/notifications'),
                child: const Text('Notification preferences'),
              ),
              if (platformUrl.isNotEmpty)
                OutlinedButton(
                  onPressed: () => context.push('/daily-climate'),
                  child: const Text(UiLabels.dailyClimateLocalEvidencePlatform),
                ),
              const SourceNote(),
            ],
          ),
        ),
      ),
    );
  }
}
