---
id: TASK-014
title: Add LikeState, the app's record of what the signed-in user has liked
depends_on: TASK-013
requires: flutter, dart
allowed: bharatverse_app/lib/state/like_state.dart, bharatverse_app/test/state/like_state_test.dart
verify: cd "$BV_ROOT/bharatverse_app" && flutter test --no-pub test/state/like_state_test.dart
verify: cd "$BV_ROOT/bharatverse_app" && dart format --output=none --set-exit-if-changed .
verify: cd "$BV_ROOT/bharatverse_app" && flutter analyze --no-pub
verify: cd "$BV_ROOT/bharatverse_app" && flutter test --no-pub --coverage
verify: cd "$BV_ROOT" && ./scripts/check_lcov_coverage.sh bharatverse_app/coverage/lcov.info 85 "lib/main.dart"
commit: feat: add LikeState
---

# TASK-014: Add LikeState, the app's record of what the signed-in user has liked

## Why

The like button needs somewhere to ask "has this user liked this article?" and something to call when they tap. `LikeState`
is that: a `ChangeNotifier` holding the ids of the articles the signed-in user has liked, synced through the
`LikesClient` from TASK-013. It follows `AuthState`: it loads the user's likes on sign-in and forgets them on
sign-out, so one user's likes never show for the next.

The behaviours that matter, each pinned by a test:

- A tap shows the change immediately and rolls it back, rethrowing the error, if the request fails.
- A second tap on an article whose first change is still in flight is ignored.
- A token refresh does not reload the likes. Only a different user does.
- A load, or a failed request's rollback, that finishes after the user signed out must not touch the next user's state.

## Conventions to match

This code follows the app's existing patterns, so copy it exactly rather than restyling it. State classes extend
`ChangeNotifier` and take their dependencies in the constructor, like `AuthState`. Services take an injectable
`http.Client` and throw `ApiException`, like `ApiClient`. Tests use `mocktail` for collaborators and `MockClient` to
assert the HTTP requests actually sent, grouped per class or method.

## Read first, and nothing else

- Nothing. `LikesClient` and `AuthState.accessToken` exist after TASK-013; you only call them.

## Steps

### Step 1. Create the state class

Create `bharatverse_app/lib/state/like_state.dart` with exactly this content:

<!-- step: create bharatverse_app/lib/state/like_state.dart -->
```dart
import 'package:flutter/foundation.dart';

import '../services/likes_client.dart';
import 'auth_state.dart';

/// Which articles the signed-in user has liked, kept in memory and synced to
/// Supabase through [LikesClient]. Follows [AuthState]: it loads the user's
/// likes on sign-in and forgets them on sign-out, so one user's likes never
/// show for the next.
class LikeState extends ChangeNotifier {
  final LikesClient _likesClient;
  final AuthState _authState;

  final Set<String> _likedIds = {};
  final Set<String> _pending = {};
  String? _loadedForUserId;

  LikeState({required LikesClient likesClient, required AuthState authState})
      : _likesClient = likesClient,
        _authState = authState {
    _authState.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  bool isLiked(String articleId) => _likedIds.contains(articleId);

  /// Likes the article if it is not liked, and unlikes it if it is. The change
  /// shows immediately and is rolled back if the request fails, in which case
  /// the error is rethrown. A tap on an article whose previous change is still
  /// in flight is ignored. Throws a [StateError] when nobody is signed in.
  Future<void> toggle(String articleId) async {
    final userId = _authState.currentUser?.id;
    final accessToken = _authState.accessToken;
    if (userId == null || accessToken == null) {
      throw StateError('Sign in to like articles');
    }
    if (!_pending.add(articleId)) {
      return;
    }

    final wasLiked = isLiked(articleId);
    _setLiked(userId, articleId, !wasLiked);
    try {
      if (wasLiked) {
        await _likesClient.unlike(
          accessToken: accessToken,
          articleId: articleId,
        );
      } else {
        await _likesClient.like(
          accessToken: accessToken,
          userId: userId,
          articleId: articleId,
        );
      }
    } catch (_) {
      _setLiked(userId, articleId, wasLiked);
      rethrow;
    } finally {
      _pending.remove(articleId);
    }
  }

  void _setLiked(String userId, String articleId, bool liked) {
    // The account may have changed while a request was in flight.
    if (_loadedForUserId != userId) {
      return;
    }
    if (liked) {
      _likedIds.add(articleId);
    } else {
      _likedIds.remove(articleId);
    }
    notifyListeners();
  }

  void _onAuthChanged() {
    final userId = _authState.currentUser?.id;
    // Token refreshes also notify; only a different user changes anything.
    if (userId == _loadedForUserId) {
      return;
    }
    _loadedForUserId = userId;
    _likedIds.clear();
    _pending.clear();
    notifyListeners();
    if (userId != null) {
      _load(userId);
    }
  }

  Future<void> _load(String userId) async {
    final accessToken = _authState.accessToken;
    if (accessToken == null) {
      return;
    }
    try {
      final ids = await _likesClient.getLikedArticleIds(
        accessToken: accessToken,
      );
      // Signed out, or a different account, by the time this returned.
      if (_loadedForUserId != userId) {
        return;
      }
      _likedIds.addAll(ids);
      notifyListeners();
    } catch (e) {
      // A failed load must not block reading. The likes stay empty until the
      // next sign-in.
      debugPrint('Could not load likes: $e');
    }
  }

  @override
  void dispose() {
    _authState.removeListener(_onAuthChanged);
    super.dispose();
  }
}
```

### Step 2. Create the tests

Create `bharatverse_app/test/state/like_state_test.dart` with exactly this content:

<!-- step: create bharatverse_app/test/state/like_state_test.dart -->
```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as gotrue
    show AuthState;

import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/services/likes_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/state/like_state.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockLikesClient extends Mock implements LikesClient {}

User testUser({String id = 'user-123'}) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-07-08T00:00:00Z',
    );

void main() {
  late MockGoTrueClient authClient;
  late MockLikesClient likesClient;
  late StreamController<gotrue.AuthState> authEvents;
  late AuthState authState;

  /// Makes the mocked auth client report [user] as signed in, or nobody.
  void signInAs(User? user, {String token = 'user-token'}) {
    when(() => authClient.currentUser).thenReturn(user);
    when(() => authClient.currentSession).thenReturn(
      user == null
          ? null
          : Session(accessToken: token, tokenType: 'bearer', user: user),
    );
  }

  /// Tells listeners the auth state changed, as Supabase would.
  Future<void> emitAuthChange(AuthChangeEvent event) async {
    authEvents.add(gotrue.AuthState(event, authClient.currentSession));
    await pumpEventQueue();
  }

  LikeState makeLikeState() =>
      LikeState(likesClient: likesClient, authState: authState);

  setUp(() {
    authClient = MockGoTrueClient();
    likesClient = MockLikesClient();
    authEvents = StreamController<gotrue.AuthState>.broadcast();
    addTearDown(authEvents.close);
    when(() => authClient.onAuthStateChange)
        .thenAnswer((_) => authEvents.stream);
    signInAs(null);
    when(() => likesClient.getLikedArticleIds(
          accessToken: any(named: 'accessToken'),
        )).thenAnswer((_) async => <String>{});
    when(() => likesClient.like(
          accessToken: any(named: 'accessToken'),
          userId: any(named: 'userId'),
          articleId: any(named: 'articleId'),
        )).thenAnswer((_) async {});
    when(() => likesClient.unlike(
          accessToken: any(named: 'accessToken'),
          articleId: any(named: 'articleId'),
        )).thenAnswer((_) async {});
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
      signInAs(testUser());
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

      signInAs(testUser());
      await emitAuthChange(AuthChangeEvent.signedIn);

      expect(likeState.isLiked('art_1'), isTrue);
    });

    test('notifies listeners once the likes have loaded', () async {
      signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final likeState = makeLikeState();
      var notified = 0;
      likeState.addListener(() => notified++);

      await pumpEventQueue();

      expect(notified, 1);
    });

    test('forgets the likes when the user signs out', () async {
      signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final likeState = makeLikeState();
      await pumpEventQueue();

      signInAs(null);
      await emitAuthChange(AuthChangeEvent.signedOut);

      expect(likeState.isLiked('art_1'), isFalse);
    });

    test("a different account never sees the previous user's likes", () async {
      signInAs(testUser(id: 'alice'), token: 'alice-token');
      when(() => likesClient.getLikedArticleIds(accessToken: 'alice-token'))
          .thenAnswer((_) async => {'art_1'});
      final likeState = makeLikeState();
      await pumpEventQueue();

      signInAs(testUser(id: 'bob'), token: 'bob-token');
      await emitAuthChange(AuthChangeEvent.signedIn);

      expect(likeState.isLiked('art_1'), isFalse);
    });

    test("does not reload when the same user's token refreshes", () async {
      signInAs(testUser());
      makeLikeState();
      await pumpEventQueue();

      await emitAuthChange(AuthChangeEvent.tokenRefreshed);

      verify(() => likesClient.getLikedArticleIds(
            accessToken: any(named: 'accessToken'),
          )).called(1);
    });

    test('ignores a load that finishes after the user signed out', () async {
      final slowLoad = Completer<Set<String>>();
      signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) => slowLoad.future);
      final likeState = makeLikeState();

      signInAs(null);
      await emitAuthChange(AuthChangeEvent.signedOut);
      slowLoad.complete({'art_1'});
      await pumpEventQueue();

      expect(likeState.isLiked('art_1'), isFalse);
    });

    test('a failed load leaves the likes empty and does not throw', () async {
      signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenThrow(ApiException('Could not reach the server'));

      final likeState = makeLikeState();
      await pumpEventQueue();

      expect(likeState.isLiked('art_1'), isFalse);
    });
  });

  group('LikeState.toggle', () {
    test('likes an unliked article, showing it immediately', () async {
      signInAs(testUser());
      final request = Completer<void>();
      when(() => likesClient.like(
            accessToken: 'user-token',
            userId: 'user-123',
            articleId: 'art_1',
          )).thenAnswer((_) => request.future);
      final likeState = makeLikeState();
      await pumpEventQueue();

      final toggled = likeState.toggle('art_1');

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
      signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final likeState = makeLikeState();
      await pumpEventQueue();

      await likeState.toggle('art_1');

      expect(likeState.isLiked('art_1'), isFalse);
      verify(() => likesClient.unlike(
            accessToken: 'user-token',
            articleId: 'art_1',
          )).called(1);
    });

    test('rolls back and rethrows when liking fails', () async {
      signInAs(testUser());
      when(() => likesClient.like(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Article not found', statusCode: 404));
      final likeState = makeLikeState();
      await pumpEventQueue();

      await expectLater(
        likeState.toggle('art_missing'),
        throwsA(isA<ApiException>()),
      );

      expect(likeState.isLiked('art_missing'), isFalse);
    });

    test('rolls back an unlike that fails', () async {
      signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      when(() => likesClient.unlike(
            accessToken: any(named: 'accessToken'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Request failed (500)', statusCode: 500));
      final likeState = makeLikeState();
      await pumpEventQueue();

      await expectLater(
        likeState.toggle('art_1'),
        throwsA(isA<ApiException>()),
      );

      expect(likeState.isLiked('art_1'), isTrue);
    });

    test('ignores a second tap while the first is still in flight', () async {
      signInAs(testUser());
      final request = Completer<void>();
      when(() => likesClient.like(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenAnswer((_) => request.future);
      final likeState = makeLikeState();
      await pumpEventQueue();

      final first = likeState.toggle('art_1');
      final second = likeState.toggle('art_1');
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
      signInAs(testUser());
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
        likeState.toggle('art_1'),
        throwsA(isA<ApiException>()),
      );

      expect(notified, 2);
    });

    test('throws a StateError when nobody is signed in', () async {
      final likeState = makeLikeState();

      expect(() => likeState.toggle('art_1'), throwsStateError);
      verifyNever(() => likesClient.like(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          ));
    });

    test('does not bring back an unlike after the account changed mid-request',
        () async {
      // Rolling back a failed unlike re-adds the id, so this is the case where
      // a rollback that ignores the account change would leak a like.
      signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final request = Completer<void>();
      when(() => likesClient.unlike(
            accessToken: any(named: 'accessToken'),
            articleId: any(named: 'articleId'),
          )).thenAnswer((_) => request.future);
      final likeState = makeLikeState();
      await pumpEventQueue();

      final toggled = likeState.toggle('art_1');
      signInAs(null);
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
      signInAs(testUser());
      clearInteractions(authClient);

      await emitAuthChange(AuthChangeEvent.signedIn);

      // A LikeState still subscribed would read the current user in response.
      verifyNever(() => authClient.currentUser);
    });
  });
}
```

## Verify

Run every `verify:` command from the front matter and make each one exit 0. CI enforces `dart format`, so if the
format check reports files, run `dart format <each file you changed>` and check again. Always pass `--no-pub` to
`flutter test` and `flutter analyze`: without it Flutter rewrites `pubspec.lock`, which you must not change. Do not
edit any file that is not listed under `allowed`.

## Definition of done

- Every step above was applied exactly as written.
- Every `verify:` command exits 0.
- Only files listed under `allowed` changed.
- You did not run git commit, checkout, reset, or push. The runner commits.

## Out of scope

Do not add any widget or screen (TASK-015) and do not register the state in `main.dart` yet. Do not change
`pubspec.yaml` or `pubspec.lock`.
