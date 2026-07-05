import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bharatverse_app/services/api_client.dart';

Map<String, dynamic> sampleArticleJson({String id = 'art_20260703_001'}) => {
      'id': id,
      'title': 'The Mauryan Empire',
      'summary': 'A summary.',
      'content': 'Content',
      'sections': [],
      'citations': [],
      'publication_date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'BharatVerse AI',
      'tags': [],
      'image_url': null,
    };

void main() {
  group('ApiClient.getDailyArticle', () {
    test('returns an Article on 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/articles/daily');
        return http.Response(jsonEncode(sampleArticleJson()), 200);
      });
      final client = ApiClient(client: mockClient);

      final article = await client.getDailyArticle();

      expect(article.id, 'art_20260703_001');
    });

    test('throws ApiException on 404', () async {
      final mockClient =
          MockClient((request) async => http.Response('{}', 404));
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

  group('ApiClient.getArticleById', () {
    test('hits the correct path and returns an Article', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/articles/art_20260703_001');
        return http.Response(jsonEncode(sampleArticleJson()), 200);
      });
      final client = ApiClient(client: mockClient);

      final article = await client.getArticleById('art_20260703_001');

      expect(article.id, 'art_20260703_001');
    });
  });
}
