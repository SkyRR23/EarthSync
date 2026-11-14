import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  const AppPreferences({this.theme = ThemeMode.system, this.language = 'en'});
  final ThemeMode theme;
  final String language;
}

final preferencesProvider =
    AsyncNotifierProvider<PreferencesNotifier, AppPreferences>(
      PreferencesNotifier.new,
    );

class PreferencesNotifier extends AsyncNotifier<AppPreferences> {
  Future<void> _writes = Future.value();
  @override
  Future<AppPreferences> build() async {
    try {
      final store = await SharedPreferences.getInstance();
      return AppPreferences(
        theme: ThemeMode.values.firstWhere(
          (m) => m.name == store.getString('ui.theme'),
          orElse: () => ThemeMode.system,
        ),
        language: store.getString('ui.language') == 'my' ? 'my' : 'en',
      );
    } catch (_) {
      return const AppPreferences();
    }
  }

  Future<void> savePreferences({ThemeMode? theme, String? language}) {
    final operation = _writes.then((_) async {
      final current = await future;
      final next = AppPreferences(
        theme: theme ?? current.theme,
        language: language ?? current.language,
      );
      final store = await SharedPreferences.getInstance();
      if (!await store.setString('ui.theme', next.theme.name) ||
          !await store.setString('ui.language', next.language)) {
        throw StateError('Could not save preferences on this device.');
      }
      if (ref.mounted) state = AsyncData(next);
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}
