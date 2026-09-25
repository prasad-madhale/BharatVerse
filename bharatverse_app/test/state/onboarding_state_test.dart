import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/state/onboarding_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OnboardingState', () {
    test('is unseen until marked', () async {
      final state = OnboardingState(await SharedPreferences.getInstance());

      expect(state.seen, isFalse);
    });

    test('remembers being seen across instances', () async {
      final prefs = await SharedPreferences.getInstance();
      await OnboardingState(prefs).markSeen();

      expect(OnboardingState(prefs).seen, isTrue);
    });

    test('open reads a persisted value', () async {
      SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});

      expect((await OnboardingState.open()).seen, isTrue);
    });
  });
}
