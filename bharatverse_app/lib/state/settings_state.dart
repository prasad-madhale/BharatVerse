import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Settings sheet's "Text size" choice -- applied to the article body
/// (see [ArticleDetailScreen]'s `_Section`).
enum TextSize {
  small(16),
  medium(18),
  large(21);

  final double points;
  const TextSize(this.points);
}

/// The Settings sheet's local, device-only preferences: notification
/// toggles, text size, and the offline-download toggle. Notifications are
/// UI + storage only -- there is no push integration (see roadmap.md), so a
/// toggle here can never mean a notification actually arrives. Offline
/// download persists but is not yet wired to [ArticleCache]'s behavior.
/// Appearance lives in [ThemeModeState], not here, since it existed first.
class SettingsState extends ChangeNotifier {
  static const _notifDailyKey = 'settings_notif_daily_v1';
  static const _notifWeeklyKey = 'settings_notif_weekly_v1';
  static const _notifAnnounceKey = 'settings_notif_announce_v1';
  static const _textSizeKey = 'settings_text_size_v1';
  static const _offlineKey = 'settings_offline_v1';

  final SharedPreferences _prefs;

  bool _notifDaily;
  bool _notifWeekly;
  bool _notifAnnounce;
  TextSize _textSize;
  bool _offlineOn;

  SettingsState(this._prefs)
      : _notifDaily = _prefs.getBool(_notifDailyKey) ?? true,
        _notifWeekly = _prefs.getBool(_notifWeeklyKey) ?? true,
        _notifAnnounce = _prefs.getBool(_notifAnnounceKey) ?? false,
        _textSize = TextSize.values.firstWhere(
          (s) => s.name == _prefs.getString(_textSizeKey),
          orElse: () => TextSize.medium,
        ),
        _offlineOn = _prefs.getBool(_offlineKey) ?? false;

  static Future<SettingsState> open() async =>
      SettingsState(await SharedPreferences.getInstance());

  bool get notifDaily => _notifDaily;
  bool get notifWeekly => _notifWeekly;
  bool get notifAnnounce => _notifAnnounce;
  TextSize get textSize => _textSize;
  bool get offlineOn => _offlineOn;

  Future<void> setNotifDaily(bool value) =>
      _setBool(_notifDailyKey, value, (v) => _notifDaily = v);
  Future<void> setNotifWeekly(bool value) =>
      _setBool(_notifWeeklyKey, value, (v) => _notifWeekly = v);
  Future<void> setNotifAnnounce(bool value) =>
      _setBool(_notifAnnounceKey, value, (v) => _notifAnnounce = v);
  Future<void> setOfflineOn(bool value) =>
      _setBool(_offlineKey, value, (v) => _offlineOn = v);

  Future<void> setTextSize(TextSize size) async {
    if (size == _textSize) return;
    _textSize = size;
    notifyListeners();
    await _prefs.setString(_textSizeKey, size.name);
  }

  Future<void> _setBool(
      String key, bool value, void Function(bool) apply) async {
    apply(value);
    notifyListeners();
    await _prefs.setBool(key, value);
  }
}
