import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/state/theme_mode_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ThemeModeState', () {
    test('defaults to system when nothing is persisted', () async {
      final state = ThemeModeState(await SharedPreferences.getInstance());

      expect(state.mode, ThemeMode.system);
    });

    test('setMode notifies listeners and persists the choice', () async {
      final prefs = await SharedPreferences.getInstance();
      final state = ThemeModeState(prefs);
      var notified = 0;
      state.addListener(() => notified++);

      await state.setMode(ThemeMode.dark);

      expect(state.mode, ThemeMode.dark);
      expect(notified, 1);
      expect(ThemeModeState(prefs).mode, ThemeMode.dark);
    });

    test('setMode to the current mode does nothing', () async {
      final state = ThemeModeState(await SharedPreferences.getInstance());
      var notified = 0;
      state.addListener(() => notified++);

      await state.setMode(ThemeMode.system);

      expect(notified, 0);
    });

    test('open reads a persisted value', () async {
      SharedPreferences.setMockInitialValues({'theme_mode_v1': 'light'});

      expect((await ThemeModeState.open()).mode, ThemeMode.light);
    });

    test('an unrecognised persisted value falls back to system', () async {
      SharedPreferences.setMockInitialValues({'theme_mode_v1': 'sepia'});

      expect((await ThemeModeState.open()).mode, ThemeMode.system);
    });
  });
}
