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
      AuthException(:final message) => message,
      _ => describeError(error),
    };

/// Auth state for the app, backed directly by Supabase Auth's client SDK
/// (not our own backend's /auth/* REST endpoints) so session persistence
/// and refresh are handled automatically by the SDK -- see roadmap.md
/// Phase 1. OAuth (Google/Facebook) is deferred to a fast-follow.
class AuthState extends ChangeNotifier {
  final GoTrueClient _authClient;

  AuthState({GoTrueClient? authClient})
      : _authClient = authClient ?? Supabase.instance.client.auth {
    _authClient.onAuthStateChange.listen((_) => notifyListeners());
  }

  User? get currentUser => _authClient.currentUser;
  bool get isAuthenticated => currentUser != null;

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
}
