import 'package:flutter/foundation.dart';
// GoTrueClient/User are re-exported here, but we hide gotrue's own AuthState
// type since it would otherwise collide with the AuthState class below.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../services/api_client.dart';

/// What to show a reader when an auth request fails: Supabase's own message
/// when it refuses one (wrong password, weak password), a plain one when the
/// server cannot be reached, and a generic one for anything else.
String describeAuthError(Object error) => switch (error) {
      AuthRetryableFetchException(statusCode: null) => unreachableMessage,
      AuthRetryableFetchException() ||
      AuthUnknownException() =>
        describeError(error),
      AuthSessionMissingException() =>
        'Your session has ended. Please sign in again.',
      AuthException(:final message) => message,
      _ => describeError(error),
    };

/// Auth state for the app, backed directly by Supabase Auth's client SDK
/// (not our own backend's /auth/* REST endpoints) so session persistence
/// and refresh are handled automatically by the SDK -- see roadmap.md
/// Phase 1. OAuth (Google/Facebook) is deferred to a fast-follow.
class AuthState extends ChangeNotifier {
  final GoTrueClient _authClient;

  /// Where the emailed link brings the reader back to: this page on the web.
  /// A phone would need the app registered for a link scheme first.
  final String? _resetRedirectTo;

  bool _recovering = false;

  AuthState({GoTrueClient? authClient, String? resetRedirectTo})
      : _authClient = authClient ?? Supabase.instance.client.auth,
        _resetRedirectTo = resetRedirectTo ??
            (kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : null) {
    _authClient.onAuthStateChange.listen((change) {
      if (change.event == AuthChangeEvent.passwordRecovery) {
        _recovering = true;
      } else if (change.event == AuthChangeEvent.signedOut) {
        _recovering = false;
      }
      notifyListeners();
    });
  }

  User? get currentUser => _authClient.currentUser;
  bool get isAuthenticated => currentUser != null;

  /// True from the moment the reader follows a password-reset link until they
  /// choose a new password or skip it. The link has already signed them in.
  bool get isRecovering => _recovering;

  /// The signed-in user's access token; null when signed out.
  String? get authToken => _authClient.currentSession?.accessToken;

  Future<void> register(String email, String password) async {
    await _authClient.signUp(email: email, password: password);
  }

  Future<void> login(String email, String password) async {
    await _authClient.signInWithPassword(email: email, password: password);
  }

  Future<void> logout() async {
    await _authClient.signOut();
  }

  /// Has Supabase email [email] a link for choosing a new password. It
  /// succeeds the same way whether or not an account exists.
  Future<void> sendPasswordReset(String email) =>
      _authClient.resetPasswordForEmail(email, redirectTo: _resetRedirectTo);

  /// Sets the signed-in user's password, which ends a recovery.
  Future<void> updatePassword(String password) async {
    await _authClient.updateUser(UserAttributes(password: password));
    finishRecovery();
  }

  void finishRecovery() {
    _recovering = false;
    notifyListeners();
  }
}
