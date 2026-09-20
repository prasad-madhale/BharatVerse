import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A row of the `articles` table as PostgREST returns it: `date`, not
/// `publication_date`, and no content (that lives in a Storage blob).
Map<String, dynamic> sampleArticleRow({
  String id = 'art_20260703_001',
  String title = 'The Mauryan Empire',
}) =>
    {
      'id': id,
      'title': title,
      'summary': 'A summary of the Mauryan Empire.',
      'date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'BharatVerse AI',
      'tags': ['mauryan-empire'],
      'image_url': null,
      'content_file_path': 'articles/2026-07-03/$id.json',
    };

/// The content JSON a row's `content_file_path` points to in Storage.
Map<String, dynamic> sampleArticleContent() => {
      'content': '## Origins\n\nSome content.',
      'sections': [
        {'heading': 'Origins', 'content': 'Some content.', 'order': 1},
      ],
      'citations': [],
    };

/// A MockClient serving [rows] for the PostgREST call and a fixed content
/// blob for the Storage call. [onRequest] sees each PostgREST request.
MockClient articlesMockClient(
  List<Map<String, dynamic>> Function() rows, {
  void Function(http.Request request)? onRequest,
}) =>
    MockClient((request) async {
      if (request.url.path.contains('/storage/')) {
        return http.Response(jsonEncode(sampleArticleContent()), 200);
      }
      onRequest?.call(request);
      return http.Response(jsonEncode(rows()), 200);
    });
