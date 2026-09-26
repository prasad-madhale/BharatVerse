import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/state/settings_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SettingsState', () {
    test('defaults match the mockup', () async {
      final state = SettingsState(await SharedPreferences.getInstance());

      expect(state.notifDaily, isTrue);
      expect(state.notifWeekly, isTrue);
      expect(state.notifAnnounce, isFalse);
      expect(state.textSize, TextSize.medium);
      expect(state.offlineOn, isFalse);
    });

    test('each setter notifies listeners and persists', () async {
      final prefs = await SharedPreferences.getInstance();
      final state = SettingsState(prefs);
      var notified = 0;
      state.addListener(() => notified++);

      await state.setNotifDaily(false);
      await state.setNotifWeekly(false);
      await state.setNotifAnnounce(true);
      await state.setTextSize(TextSize.large);
      await state.setOfflineOn(true);

      expect(notified, 5);
      final reopened = SettingsState(prefs);
      expect(reopened.notifDaily, isFalse);
      expect(reopened.notifWeekly, isFalse);
      expect(reopened.notifAnnounce, isTrue);
      expect(reopened.textSize, TextSize.large);
      expect(reopened.offlineOn, isTrue);
    });

    test('setTextSize to the current size does nothing', () async {
      final state = SettingsState(await SharedPreferences.getInstance());
      var notified = 0;
      state.addListener(() => notified++);

      await state.setTextSize(TextSize.medium);

      expect(notified, 0);
    });

    test('open reads persisted values', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notif_daily_v1': false,
        'settings_text_size_v1': 'small',
        'settings_offline_v1': true,
      });

      final state = await SettingsState.open();

      expect(state.notifDaily, isFalse);
      expect(state.textSize, TextSize.small);
      expect(state.offlineOn, isTrue);
    });

    test('an unrecognised persisted text size falls back to medium', () async {
      SharedPreferences.setMockInitialValues({'settings_text_size_v1': 'huge'});

      expect((await SettingsState.open()).textSize, TextSize.medium);
    });
  });
}
