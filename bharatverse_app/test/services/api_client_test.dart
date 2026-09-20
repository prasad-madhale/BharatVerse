import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bharatverse_app/services/api_client.dart';

import '../support/article_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bharatverse_app/services/article_cache.dart';
import 'package:bharatverse_app/models/article.dart';

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
      final mockClient =
          MockClient((request) async => http.Response('[]', 200));
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

    test('throws a 404 ApiException when the article does not exist', () async {
      final mockClient =
          MockClient((request) async => http.Response('[]', 200));
      final client = ApiClient(client: mockClient);

      expect(
        () => client.getArticleById('missing'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('ApiClient.searchArticles', () {
    test('sends a websearch filter, newest first, with a limit', () async {
      final seen = <http.Request>[];
      final client = ApiClient(
        client:
            articlesMockClient(() => [sampleArticleRow()], onRequest: seen.add),
      );

      final articles = await client.searchArticles('Mauryan Empire', limit: 7);

      expect(articles.single.id, 'art_20260703_001');
      final query = seen.single.url.queryParameters;
      expect(seen.single.url.path, '/rest/v1/articles');
      expect(query['search_vector'], 'wfts(english).Mauryan Empire');
      expect(query['order'], 'date.desc');
      expect(query['limit'], '7');
    });

    test('returns twenty results by default', () async {
      final seen = <http.Request>[];
      final client = ApiClient(
        client: articlesMockClient(() => [], onRequest: seen.add),
      );

      await client.searchArticles('Ashoka');

      expect(seen.single.url.queryParameters['limit'], '20');
    });

    test('passes quoted phrases and exclusions through intact', () async {
      final seen = <http.Request>[];
      final client = ApiClient(
        client: articlesMockClient(() => [], onRequest: seen.add),
      );

      await client.searchArticles('  "Bay of Bengal" -Chola  ');

      expect(seen.single.url.queryParameters['search_vector'],
          'wfts(english)."Bay of Bengal" -Chola');
    });

    test('throws an ApiException when the request fails', () async {
      final client = ApiClient(
        client: MockClient((_) async => http.Response('boom', 500)),
      );

      expect(
        () => client.searchArticles('Ashoka'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });

  group('ApiClient.loadArticles', () {
    test("builds full articles from rows, fetching each one's content",
        () async {
      final client = ApiClient(client: articlesMockClient(() => []));

      final articles = await client.loadArticles([
        sampleArticleRow(id: 'art_1'),
        sampleArticleRow(id: 'art_2'),
      ]);

      expect(articles.map((article) => article.id), ['art_1', 'art_2']);
      expect(articles.first.sections.single.heading, 'Origins');
    });
  });

  group('ApiClient failures', () {
    test('a network failure gets a plain message without the raw error',
        () async {
      final client = ApiClient(
        client: MockClient((_) async =>
            throw http.ClientException('Failed to fetch, uri=http://internal')),
      );

      await expectLater(
        client.getDailyArticle(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message',
            'Could not reach the server. Check your connection and try again.')),
      );
    });
  });

  group('describeError', () {
    test("uses an ApiException's own message", () {
      expect(describeError(ApiException('Request failed (500)')),
          'Request failed (500)');
    });

    test('is generic for anything else', () {
      const generic = 'Something went wrong. Please try again.';
      expect(describeError(const FormatException('bad json')), generic);
      expect(describeError(null), generic);
    });
  });

  group('ApiClient.listArticles', () {
    test('asks for a page in a total newest-first order', () async {
      final seen = <http.Request>[];
      final client = ApiClient(
        client:
            articlesMockClient(() => [sampleArticleRow()], onRequest: seen.add),
      );

      final articles = await client.listArticles(page: 2, limit: 10);

      expect(articles.single.id, 'art_20260703_001');
      final query = seen.single.url.queryParameters;
      expect(seen.single.url.path, '/rest/v1/articles');
      expect(query['order'], 'date.desc,created_at.desc,id.desc');
      expect(query['offset'], '20');
      expect(query['limit'], '10');
    });

    test('starts at the first page of twenty', () async {
      final seen = <http.Request>[];
      final client = ApiClient(
        client: articlesMockClient(() => [], onRequest: seen.add),
      );

      await client.listArticles();

      expect(seen.single.url.queryParameters['offset'], '0');
      expect(seen.single.url.queryParameters['limit'], '20');
    });
  });

  group('ApiClient offline', () {
    late SharedPreferences prefs;
    late ArticleCache cache;
    late bool online;
    late int status;
    late List<Map<String, dynamic>> rows;

    ApiClient clientWith({ArticleCache? saved}) => ApiClient(
          cache: saved,
          client: MockClient((request) async {
            if (!online) {
              throw http.ClientException('Failed to fetch');
            }
            if (request.url.path.contains('/storage/')) {
              return http.Response(jsonEncode(sampleArticleContent()), 200);
            }
            return http.Response(jsonEncode(rows), status);
          }),
        );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      cache = ArticleCache(prefs);
      online = true;
      status = 200;
      rows = [
        for (var n = 5; n >= 1; n--)
          sampleArticleRow(id: 'art_$n', title: 'Article $n'),
      ];
    });

    test('saves what it loads while online', () async {
      final client = clientWith(saved: cache);

      await client.getRecentArticles();

      expect((await cache.getCachedArticles()).length, 5);
      expect(client.offline.value, isFalse);
    });

    test('answers from the saved articles when the server cannot be reached',
        () async {
      final client = clientWith(saved: cache);
      await client.getRecentArticles();
      online = false;

      final articles = await client.getRecentArticles(limit: 2);

      expect(articles.map((a) => a.id), ['art_5', 'art_4']);
      expect(client.offline.value, isTrue);

      online = true;
      await client.getRecentArticles();
      expect(client.offline.value, isFalse);
    });

    test('opens a saved article by id, and fails for one it never saw',
        () async {
      final client = clientWith(saved: cache);
      await client.getRecentArticles();
      online = false;

      expect((await client.getArticleById('art_3')).id, 'art_3');
      await expectLater(
          client.getArticleById('art_99'), throwsA(isA<ApiException>()));
    });

    test('gives the newest saved article as the daily one', () async {
      final client = clientWith(saved: cache);
      await client.getRecentArticles();
      online = false;

      expect((await client.getDailyArticle()).id, 'art_5');
    });

    test('lists the matching slice of what is saved', () async {
      final client = clientWith(saved: cache);
      await client.getRecentArticles();
      online = false;

      final page = await client.listArticles(page: 1, limit: 2);

      expect(page.map((a) => a.id), ['art_3', 'art_2']);
    });

    test('shows the server refusing a request instead of old articles',
        () async {
      final client = clientWith(saved: cache);
      await client.getRecentArticles();
      status = 500;

      await expectLater(
        client.getRecentArticles(),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
      expect(client.offline.value, isFalse);
    });

    test('fails when offline with nothing saved, or no cache at all', () async {
      online = false;

      await expectLater(clientWith(saved: cache).getRecentArticles(),
          throwsA(isA<ApiException>()));
      await expectLater(
          clientWith().getRecentArticles(), throwsA(isA<ApiException>()));
    });

    test('does not answer a search from the saved articles', () async {
      final client = clientWith(saved: cache);
      await client.getRecentArticles();
      online = false;

      await expectLater(
          client.searchArticles('ashoka'), throwsA(isA<ApiException>()));
      expect(client.offline.value, isFalse);
    });

    test('keeps reading working when the store fails', () async {
      final client = clientWith(saved: _FailingCache(prefs));

      final articles = await client.getRecentArticles();

      expect(articles.length, 5);
    });

    test('markViewed saves an article and keeps it from eviction', () async {
      var clock = DateTime(2026, 9, 20);
      final small = ArticleCache(prefs, capacity: 2, now: () => clock);
      final client = clientWith(saved: small);
      await small.cacheArticle(sampleArticle(id: 'a'));
      clock = clock.add(const Duration(minutes: 1));
      await small.cacheArticle(sampleArticle(id: 'b'));
      clock = clock.add(const Duration(minutes: 1));

      await client.markViewed(sampleArticle(id: 'a'));
      clock = clock.add(const Duration(minutes: 1));
      await small.cacheArticle(sampleArticle(id: 'c'));

      final ids = [for (final a in await small.getCachedArticles()) a.id]
        ..sort();
      expect(ids, ['a', 'c']);
    });
  });
}

class _FailingCache extends ArticleCache {
  _FailingCache(super.prefs);

  @override
  Future<void> cacheArticles(Iterable<Article> articles) =>
      throw StateError('storage is full');
}
