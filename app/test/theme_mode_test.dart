import 'package:earthsync/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('screen colours: light by default, the choice is saved', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer make() =>
        ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);

    final a = make();
    addTearDown(a.dispose);
    expect(a.read(themeModeProvider), ThemeMode.light);
    a.read(themeModeProvider.notifier).set(ThemeMode.dark);
    expect(prefs.getString('theme_mode'), 'dark');

    final b = make(); // app opened again
    addTearDown(b.dispose);
    expect(b.read(themeModeProvider), ThemeMode.dark);
  });
}
