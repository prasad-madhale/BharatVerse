import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as gotrue
    show AuthState;

import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/state/like_state.dart';

import '../support/like_fixtures.dart';

void main() {
  late MockGoTrueClient authClient;
  late MockLikesClient likesClient;
  late StreamController<gotrue.AuthState> authEvents;
  late AuthState authState;

  /// Tells listeners the auth state changed, as Supabase would.
  Future<void> emitAuthChange(AuthChangeEvent event) async {
    authEvents.add(gotrue.AuthState(event, authClient.currentSession));
    await pumpEventQueue();
  }

  LikeState makeLikeState() =>
      LikeState(likesClient: likesClient, authState: authState);

  setUp(() {
    authClient = MockGoTrueClient()..signInAs(null);
    likesClient = stubLikesClient();
    authEvents = StreamController<gotrue.AuthState>.broadcast();
    addTearDown(authEvents.close);
    when(() => authClient.onAuthStateChange)
        .thenAnswer((_) => authEvents.stream);
    authState = AuthState(authClient: authClient);
  });

  group('LikeState loading', () {
    test('nothing is liked, and nothing is fetched, when signed out', () {
      final likeState = makeLikeState();

      expect(likeState.isLiked('art_1'), isFalse);
      verifyNever(() => likesClient.getLikedArticleIds(
            accessToken: any(named: 'accessToken'),
          ));
    });

    test("loads the user's likes when already signed in", () async {
      authClient.signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});

      final likeState = makeLikeState();
      await pumpEventQueue();

      expect(likeState.isLiked('art_1'), isTrue);
      expect(likeState.isLiked('art_2'), isFalse);
    });

    test('loads the likes when a user signs in later', () async {
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final likeState = makeLikeState();

      authClient.signInAs(testUser());
      await emitAuthChange(AuthChangeEvent.signedIn);

      expect(likeState.isLiked('art_1'), isTrue);
    });

    test('notifies listeners once the likes have loaded', () async {
      authClient.signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final likeState = makeLikeState();
      var notified = 0;
      likeState.addListener(() => notified++);

      await pumpEventQueue();

      expect(notified, 1);
    });

    test('forgets the likes when the user signs out', () async {
      authClient.signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final likeState = makeLikeState();
      await pumpEventQueue();

      authClient.signInAs(null);
      await emitAuthChange(AuthChangeEvent.signedOut);

      expect(likeState.isLiked('art_1'), isFalse);
    });

    test("a different account never sees the previous user's likes", () async {
      authClient.signInAs(testUser(id: 'alice'), token: 'alice-token');
      when(() => likesClient.getLikedArticleIds(accessToken: 'alice-token'))
          .thenAnswer((_) async => {'art_1'});
      final likeState = makeLikeState();
      await pumpEventQueue();

      authClient.signInAs(testUser(id: 'bob'), token: 'bob-token');
      await emitAuthChange(AuthChangeEvent.signedIn);

      expect(likeState.isLiked('art_1'), isFalse);
    });

    test("does not reload when the same user's token refreshes", () async {
      authClient.signInAs(testUser());
      makeLikeState();
      await pumpEventQueue();

      await emitAuthChange(AuthChangeEvent.tokenRefreshed);

      verify(() => likesClient.getLikedArticleIds(
            accessToken: any(named: 'accessToken'),
          )).called(1);
    });

    test('ignores a load that finishes after the user signed out', () async {
      final slowLoad = Completer<Set<String>>();
      authClient.signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) => slowLoad.future);
      final likeState = makeLikeState();

      authClient.signInAs(null);
      await emitAuthChange(AuthChangeEvent.signedOut);
      slowLoad.complete({'art_1'});
      await pumpEventQueue();

      expect(likeState.isLiked('art_1'), isFalse);
    });

    test('a failed load leaves the likes empty and does not throw', () async {
      authClient.signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenThrow(ApiException('Could not reach the server'));

      final likeState = makeLikeState();
      await pumpEventQueue();

      expect(likeState.isLiked('art_1'), isFalse);
    });
  });

  group('LikeState.toggleLike', () {
    test('likes an unliked article, showing it immediately', () async {
      authClient.signInAs(testUser());
      final request = Completer<void>();
      when(() => likesClient.like(
            accessToken: 'user-token',
            userId: 'user-123',
            articleId: 'art_1',
          )).thenAnswer((_) => request.future);
      final likeState = makeLikeState();
      await pumpEventQueue();

      final toggled = likeState.toggleLike('art_1');

      expect(likeState.isLiked('art_1'), isTrue);
      request.complete();
      await toggled;
      verify(() => likesClient.like(
            accessToken: 'user-token',
            userId: 'user-123',
            articleId: 'art_1',
          )).called(1);
    });

    test('unlikes a liked article', () async {
      authClient.signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final likeState = makeLikeState();
      await pumpEventQueue();

      await likeState.toggleLike('art_1');

      expect(likeState.isLiked('art_1'), isFalse);
      verify(() => likesClient.unlike(
            accessToken: 'user-token',
            articleId: 'art_1',
          )).called(1);
    });

    test('rolls back and rethrows when liking fails', () async {
      authClient.signInAs(testUser());
      when(() => likesClient.like(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Article not found', statusCode: 404));
      final likeState = makeLikeState();
      await pumpEventQueue();

      await expectLater(
        likeState.toggleLike('art_missing'),
        throwsA(isA<ApiException>()),
      );

      expect(likeState.isLiked('art_missing'), isFalse);
    });

    test('rolls back an unlike that fails', () async {
      authClient.signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      when(() => likesClient.unlike(
            accessToken: any(named: 'accessToken'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Request failed (500)', statusCode: 500));
      final likeState = makeLikeState();
      await pumpEventQueue();

      await expectLater(
        likeState.toggleLike('art_1'),
        throwsA(isA<ApiException>()),
      );

      expect(likeState.isLiked('art_1'), isTrue);
    });

    test('ignores a second tap while the first is still in flight', () async {
      authClient.signInAs(testUser());
      final request = Completer<void>();
      when(() => likesClient.like(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenAnswer((_) => request.future);
      final likeState = makeLikeState();
      await pumpEventQueue();

      final first = likeState.toggleLike('art_1');
      final second = likeState.toggleLike('art_1');
      request.complete();
      await Future.wait([first, second]);

      expect(likeState.isLiked('art_1'), isTrue);
      verify(() => likesClient.like(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).called(1);
    });

    test('notifies listeners on the optimistic change and on a rollback',
        () async {
      authClient.signInAs(testUser());
      when(() => likesClient.like(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Request failed (500)', statusCode: 500));
      final likeState = makeLikeState();
      await pumpEventQueue();
      var notified = 0;
      likeState.addListener(() => notified++);

      await expectLater(
        likeState.toggleLike('art_1'),
        throwsA(isA<ApiException>()),
      );

      expect(notified, 2);
    });

    test('throws a StateError when nobody is signed in', () async {
      final likeState = makeLikeState();

      expect(() => likeState.toggleLike('art_1'), throwsStateError);
      verifyNever(() => likesClient.like(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          ));
    });

    test('does not bring back an unlike after the account changed mid-request',
        () async {
      // A rollback that ignores the account change would re-add the id and leak a like.
      authClient.signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final request = Completer<void>();
      when(() => likesClient.unlike(
            accessToken: any(named: 'accessToken'),
            articleId: any(named: 'articleId'),
          )).thenAnswer((_) => request.future);
      final likeState = makeLikeState();
      await pumpEventQueue();

      final toggled = likeState.toggleLike('art_1');
      authClient.signInAs(null);
      await emitAuthChange(AuthChangeEvent.signedOut);
      request.completeError(ApiException('Request failed (500)'));
      await expectLater(toggled, throwsA(isA<ApiException>()));

      expect(likeState.isLiked('art_1'), isFalse);
    });
  });

  group('LikeState.dispose', () {
    test('stops following auth changes', () async {
      final likeState = makeLikeState();
      likeState.dispose();
      authClient.signInAs(testUser());
      clearInteractions(authClient);

      await emitAuthChange(AuthChangeEvent.signedIn);

      // A LikeState still subscribed would read the current user in response.
      verifyNever(() => authClient.currentUser);
    });
  });
}
