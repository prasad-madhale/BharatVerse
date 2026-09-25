import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's Light/Dark/System appearance choice (the Settings sheet's
/// "Appearance" row), persisted on-device -- there is no server-side user
/// preference storage (see docs/roadmap.md), so this follows the same
/// SharedPreferences-backed, `.open()`-factory convention as
/// ArticleCache/PendingLikes rather than syncing anywhere.
class ThemeModeState extends ChangeNotifier {
  static const _key = 'theme_mode_v1';

  final SharedPreferences _prefs;
  ThemeMode _mode;

  ThemeModeState(this._prefs) : _mode = _readMode(_prefs);

  static Future<ThemeModeState> open() async =>
      ThemeModeState(await SharedPreferences.getInstance());

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) {
      return;
    }
    _mode = mode;
    notifyListeners();
    await _prefs.setString(_key, mode.name);
  }

  static ThemeMode _readMode(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    return ThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => ThemeMode.system,
    );
  }
}
