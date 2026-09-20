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
