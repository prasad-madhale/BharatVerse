import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bharatverse_app/models/article.dart';

/// A row of the `articles` table as PostgREST returns it: `date`, not
/// `publication_date`, and no content (that lives in a Storage blob).
Map<String, dynamic> sampleArticleRow({
  String id = 'art_20260703_001',
  String title = 'The Mauryan Empire',
  String date = '2026-07-03',
  List<String> tags = const ['mauryan-empire'],
  String? imageUrl,
}) =>
    {
      'id': id,
      'title': title,
      'summary': 'A summary of the Mauryan Empire.',
      'date': date,
      'reading_time_minutes': 13,
      'author': 'BharatVerse AI',
      'tags': tags,
      'image_url': imageUrl,
      'content_file_path': 'articles/2026-07-03/$id.json',
    };

/// The content JSON a row's `content_file_path` points to in Storage.
Map<String, dynamic> sampleArticleContent({
  List<Map<String, dynamic>> images = const [],
}) =>
    {
      'content': '## Origins\n\nSome content.',
      'sections': [
        {'heading': 'Origins', 'content': 'Some content.', 'order': 1},
      ],
      'citations': [],
      'images': images,
    };

/// One ArticleImage, as its JSON, for tests that need a real image entry.
Map<String, dynamic> sampleImage({
  String url = 'https://storage.example/0.jpg',
  String? caption = 'A restored Mauryan-era stupa',
}) =>
    {
      'url': url,
      'alt_text': 'The Great Stupa',
      'caption': caption,
      'credit': 'Jane Doe via Wikimedia Commons',
      'source_url': 'https://commons.wikimedia.org/wiki/File:Stupa.jpg',
      'license': 'CC BY-SA 4.0',
    };

/// A MockClient serving [rows] for the PostgREST call and a fixed content
/// blob for the Storage call. [onRequest] sees each PostgREST request.
/// Suggestion requests get no suggestions; see [searchMockClient] to script them.
MockClient articlesMockClient(
  List<Map<String, dynamic>> Function() rows, {
  void Function(http.Request request)? onRequest,
}) =>
    searchMockClient(rows: rows, onRequest: onRequest);

/// Like [articlesMockClient], and [suggest] answers each request for search
/// suggestions with the terms for the typed prefix, or null for a server error.
MockClient searchMockClient({
  List<Map<String, dynamic>> Function()? rows,
  Future<List<String>?> Function(String prefix)? suggest,
  void Function(http.Request request)? onRequest,
}) =>
    MockClient((request) async {
      if (request.url.path.contains('/storage/')) {
        return jsonResponse(sampleArticleContent());
      }
      onRequest?.call(request);
      if (request.url.path.endsWith('/rpc/autocomplete_suggestions')) {
        final prefix = (jsonDecode(request.body) as Map)['prefix'] as String;
        final terms = await (suggest ?? (_) async => <String>[])(prefix);
        return terms == null
            ? http.Response('boom', 500)
            : jsonResponse([
                for (final term in terms) {'term': term}
              ]);
      }
      return jsonResponse((rows ?? () => [sampleArticleRow()])());
    });

/// A 200 response with [body] as UTF-8 JSON, as PostgREST sends it, so text in
/// any script survives (a plain `http.Response(String)` is Latin-1).
http.Response jsonResponse(Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// A full [Article], assembled the way ApiClient does from a row and its
/// content.
Article sampleArticle({
  String id = 'art_20260703_001',
  String title = 'The Mauryan Empire',
  String date = '2026-07-03',
  List<String> tags = const ['mauryan-empire'],
  String? imageUrl,
  List<Map<String, dynamic>> images = const [],
}) =>
    Article.fromJson({
      ...sampleArticleRow(
          id: id, title: title, date: date, tags: tags, imageUrl: imageUrl),
      'publication_date': date,
      ...sampleArticleContent(images: images),
    });
