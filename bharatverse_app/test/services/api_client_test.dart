import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bharatverse_app/services/api_client.dart';

/// Shape of a row returned by Supabase's REST (PostgREST) API for the
/// `articles` table -- note `date`, not `publication_date`, and no
/// content/sections/citations (those live in a separate Storage blob).
Map<String, dynamic> sampleArticleRow({String id = 'art_20260703_001'}) => {
      'id': id,
      'title': 'The Mauryan Empire',
      'summary': 'A summary.',
      'date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'BharatVerse AI',
      'tags': [],
      'image_url': null,
      'content_file_path': 'articles/2026-07-03/$id.json',
    };

/// Shape of the content JSON downloaded from Supabase Storage for a row's
/// `content_file_path`.
Map<String, dynamic> sampleArticleContent() => {
      'content': 'Content',
      'sections': [],
      'citations': [],
    };

/// A MockClient that serves `rows` for ApiClient's PostgREST call and a
/// fixed content blob for its Storage call, branching on the request path
/// the same way ApiClient's two calls do.
MockClient articlesMockClient(List<Map<String, dynamic>> Function() rows) =>
    MockClient((request) async {
      if (request.url.path.contains('/storage/')) {
        return http.Response(jsonEncode(sampleArticleContent()), 200);
      }
      return http.Response(jsonEncode(rows()), 200);
    });

void main() {
  group('ApiClient.getDailyArticle', () {
    test('returns an Article on 200', () async {
      final mockClient = articlesMockClient(() => [sampleArticleRow()]);
      final client = ApiClient(client: mockClient);

      final article = await client.getDailyArticle();

      expect(article.id, 'art_20260703_001');
    });

    test('queries the articles table ordered by date, limit 1', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/storage/')) {
          return http.Response(jsonEncode(sampleArticleContent()), 200);
        }
        expect(request.url.path, '/rest/v1/articles');
        expect(request.url.queryParameters['order'], 'date.desc');
        expect(request.url.queryParameters['limit'], '1');
        return http.Response(jsonEncode([sampleArticleRow()]), 200);
      });
      final client = ApiClient(client: mockClient);

      await client.getDailyArticle();
    });

    test('throws a 404 ApiException when no articles exist', () async {
      final mockClient = MockClient((request) async => http.Response('[]', 200));
      final client = ApiClient(client: mockClient);

      expect(
        () => client.getDailyArticle(),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('throws ApiException on server error', () async {
      final mockClient =
          MockClient((request) async => http.Response('error', 500));
      final client = ApiClient(client: mockClient);

      expect(
        () => client.getDailyArticle(),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('throws ApiException when the network request fails', () async {
      final mockClient =
          MockClient((request) async => throw Exception('network down'));
      final client = ApiClient(client: mockClient);

      expect(() => client.getDailyArticle(), throwsA(isA<ApiException>()));
    });
  });

  group('ApiClient.getRecentArticles', () {
    test('returns a list of Articles on 200', () async {
      final mockClient = articlesMockClient(() => [
            sampleArticleRow(id: 'art_20260703_001'),
            sampleArticleRow(id: 'art_20260703_002'),
          ]);
      final client = ApiClient(client: mockClient);

      final articles = await client.getRecentArticles();

      expect(
          articles.map((a) => a.id), ['art_20260703_001', 'art_20260703_002']);
    });

    test('defaults limit to 5 in the query string', () async {
      final mockClient = MockClient((request) async {
        if (!request.url.path.contains('/storage/')) {
          expect(request.url.queryParameters['limit'], '5');
        }
        return http.Response('[]', 200);
      });
      final client = ApiClient(client: mockClient);

      await client.getRecentArticles();
    });

    test('passes a custom limit through', () async {
      final mockClient = MockClient((request) async {
        if (!request.url.path.contains('/storage/')) {
          expect(request.url.queryParameters['limit'], '2');
        }
        return http.Response('[]', 200);
      });
      final client = ApiClient(client: mockClient);

      await client.getRecentArticles(limit: 2);
    });

    test('returns an empty list when there are no articles', () async {
      final mockClient =
          MockClient((request) async => http.Response('[]', 200));
      final client = ApiClient(client: mockClient);

      final articles = await client.getRecentArticles();

      expect(articles, isEmpty);
    });

    test('throws ApiException on server error', () async {
      final mockClient =
          MockClient((request) async => http.Response('error', 500));
      final client = ApiClient(client: mockClient);

      expect(
        () => client.getRecentArticles(),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });

  group('ApiClient.getArticleById', () {
    test('filters by id and returns an Article', () async {
      final mockClient = MockClient((request) async {
        if (!request.url.path.contains('/storage/')) {
          expect(request.url.path, '/rest/v1/articles');
          expect(request.url.queryParameters['id'], 'eq.art_20260703_001');
          return http.Response(jsonEncode([sampleArticleRow()]), 200);
        }
        return http.Response(jsonEncode(sampleArticleContent()), 200);
      });
      final client = ApiClient(client: mockClient);

      final article = await client.getArticleById('art_20260703_001');

      expect(article.id, 'art_20260703_001');
    });

    test('throws a 404 ApiException when the article does not exist',
        () async {
      final mockClient = MockClient((request) async => http.Response('[]', 200));
      final client = ApiClient(client: mockClient);

      expect(
        () => client.getArticleById('missing'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });
}
