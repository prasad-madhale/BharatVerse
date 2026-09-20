---
id: TASK-013
title: Add LikesClient and expose the user's access token from AuthState
depends_on: 
requires: flutter, dart
allowed: bharatverse_app/lib/services/likes_client.dart, bharatverse_app/lib/state/auth_state.dart, bharatverse_app/test/services/likes_client_test.dart, bharatverse_app/test/state/auth_state_test.dart
verify: cd "$BV_ROOT/bharatverse_app" && flutter test --no-pub test/services/likes_client_test.dart test/state/auth_state_test.dart
verify: cd "$BV_ROOT/bharatverse_app" && dart format --output=none --set-exit-if-changed .
verify: cd "$BV_ROOT/bharatverse_app" && flutter analyze --no-pub
verify: cd "$BV_ROOT/bharatverse_app" && flutter test --no-pub --coverage
verify: cd "$BV_ROOT" && ./scripts/check_lcov_coverage.sh bharatverse_app/coverage/lcov.info 85 "lib/main.dart"
commit: feat: add LikesClient and expose the access token from AuthState
---

# TASK-013: Add LikesClient and expose the user's access token from AuthState

## Why

The app needs a like button. Likes live in the `likes` table, whose row-level security policies let a user see and
change only their own rows. The anon key that `ApiClient` uses for public reads therefore sees and changes nothing:
every request has to carry the signed-in user's own access token.

This task adds `LikesClient`, which reads, upserts, and deletes likes straight through Supabase's REST (PostgREST)
API, the same route `ApiClient` takes for articles, so no backend has to be deployed. It also adds an `accessToken`
getter to `AuthState`, so the next task can pass the token along.

## Conventions to match

This code follows the app's existing patterns, so copy it exactly rather than restyling it. State classes extend
`ChangeNotifier` and take their dependencies in the constructor, like `AuthState`. Services take an injectable
`http.Client` and throw `ApiException`, like `ApiClient`. Tests use `mocktail` for collaborators and `MockClient` to
assert the HTTP requests actually sent, grouped per class or method.

## Read first, and nothing else

- `bharatverse_app/lib/state/auth_state.dart`
- `bharatverse_app/test/state/auth_state_test.dart`, only its last lines

## Steps

### Step 1. Create the client

Create `bharatverse_app/lib/services/likes_client.dart` with exactly this content:

<!-- step: create bharatverse_app/lib/services/likes_client.dart -->
```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'api_client.dart';

/// Reads and writes the signed-in user's likes straight through Supabase's
/// REST (PostgREST) API. Unlike [ApiClient]'s public reads, every call here
/// carries the *user's* access token: the `likes` table's row-level security
/// (see backend/database/schema.sql) only lets a user see and change their
/// own rows, so the anon key alone would see and change nothing.
class LikesClient {
  /// Supabase project URL. Override only for tests.
  final String baseUrl;
  final http.Client _client;

  LikesClient({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ?? supabaseUrl,
        _client = client ?? http.Client();

  /// Ids of the articles the token's user has liked.
  Future<Set<String>> getLikedArticleIds({required String accessToken}) async {
    final response = await _send(
      'GET',
      {'select': 'article_id'},
      accessToken: accessToken,
    );
    return (jsonDecode(response.body) as List<dynamic>)
        .map((row) => (row as Map<String, dynamic>)['article_id'] as String)
        .toSet();
  }

  /// Records a like. Idempotent: liking twice is not an error. The table has a
  /// unique (user_id, article_id) index, and `ignore-duplicates` (ON CONFLICT DO
  /// NOTHING) skips the second insert. It is not `merge-duplicates` because the
  /// table has no UPDATE policy, so row-level security would refuse the update
  /// that merging performs on an existing row.
  Future<void> like({
    required String accessToken,
    required String userId,
    required String articleId,
  }) async {
    await _send(
      'POST',
      {'on_conflict': 'user_id,article_id'},
      accessToken: accessToken,
      headers: {'Prefer': 'resolution=ignore-duplicates'},
      body: jsonEncode({'user_id': userId, 'article_id': articleId}),
    );
  }

  /// Removes a like. Idempotent. Row-level security limits the delete to the
  /// token user's own rows.
  Future<void> unlike({
    required String accessToken,
    required String articleId,
  }) async {
    await _send(
      'DELETE',
      {'article_id': 'eq.$articleId'},
      accessToken: accessToken,
    );
  }

  Future<http.Response> _send(
    String method,
    Map<String, String> query, {
    required String accessToken,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = http.Request(
      method,
      Uri.parse('$baseUrl/rest/v1/likes').replace(queryParameters: query),
    )..headers.addAll({
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $accessToken',
        if (body != null) 'Content-Type': 'application/json',
        ...headers,
      });
    if (body != null) {
      request.body = body;
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } catch (e) {
      throw ApiException('Could not reach the server: $e');
    }

    // A conflict on insert is a foreign-key violation: there is no such article.
    if (response.statusCode == 409) {
      throw ApiException('Article not found', statusCode: 404);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Request failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    return response;
  }
}
```

### Step 2. Expose the access token

<!-- step: replace bharatverse_app/lib/state/auth_state.dart -->
Replace this exact text:

```dart
  User? get currentUser => _authClient.currentUser;
  bool get isAuthenticated => currentUser != null;
```

with this exact text:

```dart
  User? get currentUser => _authClient.currentUser;
  bool get isAuthenticated => currentUser != null;

  /// The signed-in user's access token, for requests that row-level security
  /// must attribute to them (see [LikesClient]); null when signed out.
  String? get accessToken => _authClient.currentSession?.accessToken;
```

### Step 3. Test the token getter

This adds two tests at the end of the existing `AuthState` group.

<!-- step: replace bharatverse_app/test/state/auth_state_test.dart -->
Replace this exact text:

```dart
      expect(notified, isTrue);
    });
  });
}
```

with this exact text:

```dart
      expect(notified, isTrue);
    });

    test('accessToken is the current session token', () {
      final session = Session(
        accessToken: 'user-token',
        tokenType: 'bearer',
        user: User(
          id: 'user-123',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-07-08T00:00:00Z',
        ),
      );
      when(() => mockAuthClient.currentSession).thenReturn(session);
      final authState = AuthState(authClient: mockAuthClient);

      expect(authState.accessToken, 'user-token');
    });

    test('accessToken is null when there is no session', () {
      when(() => mockAuthClient.currentSession).thenReturn(null);
      final authState = AuthState(authClient: mockAuthClient);

      expect(authState.accessToken, isNull);
    });
  });
}
```

### Step 4. Create the client tests

Create `bharatverse_app/test/services/likes_client_test.dart` with exactly this content:

<!-- step: create bharatverse_app/test/services/likes_client_test.dart -->
```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bharatverse_app/config.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/services/likes_client.dart';

/// A MockClient that appends every request it receives to [seen] and answers
/// with [status] and [body], so a test can assert on what was actually sent.
MockClient recordingClient(
  List<http.Request> seen, {
  int status = 200,
  String body = '[]',
}) =>
    MockClient((request) async {
      seen.add(request);
      return http.Response(body, status);
    });

void main() {
  group('LikesClient.getLikedArticleIds', () {
    test('returns the article ids from the response rows', () async {
      final client = LikesClient(
        client: recordingClient(
          [],
          body: jsonEncode([
            {'article_id': 'art_1'},
            {'article_id': 'art_2'},
          ]),
        ),
      );

      final ids = await client.getLikedArticleIds(accessToken: 'user-token');

      expect(ids, {'art_1', 'art_2'});
    });

    test('reads only the article_id column of the likes table', () async {
      final seen = <http.Request>[];
      final client = LikesClient(client: recordingClient(seen));

      await client.getLikedArticleIds(accessToken: 'user-token');

      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, '/rest/v1/likes');
      expect(seen.single.url.queryParameters, {'select': 'article_id'});
    });

    test('authenticates as the user, not with the anon key alone', () async {
      final seen = <http.Request>[];
      final client = LikesClient(client: recordingClient(seen));

      await client.getLikedArticleIds(accessToken: 'user-token');

      expect(seen.single.headers['Authorization'], 'Bearer user-token');
      expect(seen.single.headers['apikey'], supabaseAnonKey);
    });

    test('throws an ApiException carrying the status code on failure',
        () async {
      final client = LikesClient(client: recordingClient([], status: 401));

      expect(
        () => client.getLikedArticleIds(accessToken: 'expired-token'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('wraps a network failure in an ApiException', () async {
      final client = LikesClient(
        client: MockClient((request) async => throw Exception('offline')),
      );

      expect(
        () => client.getLikedArticleIds(accessToken: 'user-token'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Could not reach the server'),
          ),
        ),
      );
    });
  });

  group('LikesClient.like', () {
    test('inserts the user and article, ignoring duplicates', () async {
      final seen = <http.Request>[];
      final client = LikesClient(client: recordingClient(seen, status: 201));

      await client.like(
        accessToken: 'user-token',
        userId: 'user-123',
        articleId: 'art_1',
      );

      final request = seen.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/likes');
      expect(request.url.queryParameters['on_conflict'], 'user_id,article_id');
      expect(request.headers['Prefer'], 'resolution=ignore-duplicates');
      expect(request.headers['Authorization'], 'Bearer user-token');
      expect(jsonDecode(request.body), {
        'user_id': 'user-123',
        'article_id': 'art_1',
      });
    });

    test('maps a foreign-key conflict to a 404 ApiException', () async {
      final client = LikesClient(client: recordingClient([], status: 409));

      expect(
        () => client.like(
          accessToken: 'user-token',
          userId: 'user-123',
          articleId: 'art_missing',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  group('LikesClient.unlike', () {
    test("deletes only the given article's row as the user", () async {
      final seen = <http.Request>[];
      final client = LikesClient(
        client: recordingClient(seen, status: 204, body: ''),
      );

      await client.unlike(accessToken: 'user-token', articleId: 'art_1');

      final request = seen.single;
      expect(request.method, 'DELETE');
      expect(request.url.path, '/rest/v1/likes');
      expect(request.url.queryParameters, {'article_id': 'eq.art_1'});
      expect(request.headers['Authorization'], 'Bearer user-token');
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

Do not add a like button or any screen (TASK-015). Do not change `ApiClient`, `pubspec.yaml`, or `pubspec.lock`. Do not
call the FastAPI backend.
