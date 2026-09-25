import 'package:shared_preferences/shared_preferences.dart';

/// Whether the reader has already been through the first-run onboarding
/// flow -- read once at startup to decide whether [OnboardingScreen] or the
/// app shell is the first screen shown. Not a ChangeNotifier: nothing needs
/// to react to it after that one decision.
class OnboardingState {
  static const _key = 'onboarding_seen_v1';

  final SharedPreferences _prefs;

  OnboardingState(this._prefs);

  static Future<OnboardingState> open() async =>
      OnboardingState(await SharedPreferences.getInstance());

  bool get seen => _prefs.getBool(_key) ?? false;

  Future<void> markSeen() => _prefs.setBool(_key, true);
}
