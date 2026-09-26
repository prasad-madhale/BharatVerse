import 'package:flutter/widgets.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:bharatverse_app/services/likes_client.dart';
import 'package:bharatverse_app/services/saves_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/state/like_state.dart';
import 'package:bharatverse_app/state/save_state.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockLikesClient extends Mock implements LikesClient {}

class MockSavesClient extends Mock implements SavesClient {}

User testUser({String id = 'user-123', String email = 'reader@example.com'}) =>
    User(
      id: id,
      email: email,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-07-08T00:00:00Z',
    );

extension SignIn on MockGoTrueClient {
  /// Reports [user] as signed in, or nobody when null.
  void signInAs(User? user, {String token = 'user-token'}) {
    when(() => currentUser).thenReturn(user);
    when(() => currentSession).thenReturn(
      user == null
          ? null
          : Session(accessToken: token, tokenType: 'bearer', user: user),
    );
  }
}

/// A signed-out auth client that emits no auth events.
MockGoTrueClient stubAuthClient() {
  final client = MockGoTrueClient()..signInAs(null);
  when(() => client.onAuthStateChange).thenAnswer((_) => const Stream.empty());
  return client;
}

/// A likes client whose calls all succeed and whose likes start empty.
MockLikesClient stubLikesClient() {
  final client = MockLikesClient();
  when(() => client.getLikedArticleIds(accessToken: any(named: 'accessToken')))
      .thenAnswer((_) async => <String>{});
  when(() => client.like(
        accessToken: any(named: 'accessToken'),
        userId: any(named: 'userId'),
        articleId: any(named: 'articleId'),
      )).thenAnswer((_) async {});
  when(() => client.unlike(
        accessToken: any(named: 'accessToken'),
        articleId: any(named: 'articleId'),
      )).thenAnswer((_) async {});
  return client;
}

/// A saves client whose calls all succeed and whose saves start empty.
MockSavesClient stubSavesClient() {
  final client = MockSavesClient();
  when(() => client.getSavedArticleIds(accessToken: any(named: 'accessToken')))
      .thenAnswer((_) async => <String>{});
  when(() => client.save(
        accessToken: any(named: 'accessToken'),
        userId: any(named: 'userId'),
        articleId: any(named: 'articleId'),
      )).thenAnswer((_) async {});
  when(() => client.unsave(
        accessToken: any(named: 'accessToken'),
        articleId: any(named: 'articleId'),
      )).thenAnswer((_) async {});
  return client;
}

/// Provides [authState] and the [LikeState]/[SaveState] that follow it, as main.dart does.
Widget withLikeProviders({
  required AuthState authState,
  required LikesClient likesClient,
  required SavesClient savesClient,
  required Widget child,
}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authState),
        Provider<LikesClient>.value(value: likesClient),
        ChangeNotifierProvider(
          create: (_) =>
              LikeState(likesClient: likesClient, authState: authState),
        ),
        Provider<SavesClient>.value(value: savesClient),
        ChangeNotifierProvider(
          create: (_) =>
              SaveState(savesClient: savesClient, authState: authState),
        ),
      ],
      child: child,
    );
