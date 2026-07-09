import 'package:flutter/foundation.dart';
// GoTrueClient/User are re-exported here, but we hide gotrue's own AuthState
// type since it would otherwise collide with the AuthState class below.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

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
