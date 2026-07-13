import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/article.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Supabase Storage bucket articles' content JSON lives in -- mirrors the
/// backend's default (see backend/config.py's articles_storage_bucket).
const _articlesBucket = 'articles';

/// Reads articles straight from Supabase's REST (PostgREST) and Storage
/// HTTP APIs using the anon key -- the same credentials and RLS-gated
/// access the FastAPI backend's read endpoints use (see
/// backend/services/article_service.py). This works identically on web,
/// simulator, and a real device on any network, since it never depends on
/// a local dev server being reachable.
class ApiClient {
  /// Supabase project URL. Override only for tests.
  final String baseUrl;
  final http.Client _client;

  ApiClient({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ?? supabaseUrl,
        _client = client ?? http.Client();

  Future<Article> getDailyArticle() async {
    final rows = await _fetchRows('select=*&order=date.desc&limit=1');
    if (rows.isEmpty) {
      throw ApiException('No articles available', statusCode: 404);
    }
    return _loadArticle(rows.first);
  }

  Future<Article> getArticleById(String id) async {
    final rows = await _fetchRows('select=*&id=eq.$id&limit=1');
    if (rows.isEmpty) {
      throw ApiException('Article not found', statusCode: 404);
    }
    return _loadArticle(rows.first);
  }

  Future<List<Article>> getRecentArticles({int limit = 5}) async {
    final rows =
        await _fetchRows('select=*&order=date.desc&limit=$limit');
    return Future.wait(rows.map(_loadArticle));
  }

  /// Fetches metadata rows from the `articles` table via PostgREST.
  Future<List<Map<String, dynamic>>> _fetchRows(String query) async {
    final response = await _get('$baseUrl/rest/v1/articles?$query');
    return (jsonDecode(response.body) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  /// Downloads the full article content (content/sections/citations) and
  /// merges it with its metadata row into the flat shape Article.fromJson
  /// expects. The Postgres column is `date`, not `publication_date` --
  /// rename it here to match.
  Future<Article> _loadArticle(Map<String, dynamic> row) async {
    final contentPath = row['content_file_path'] as String;
    final response =
        await _get('$baseUrl/storage/v1/object/$_articlesBucket/$contentPath');
    final blob = jsonDecode(response.body) as Map<String, dynamic>;

    return Article.fromJson({
      ...row,
      'publication_date': row['date'],
      'content': blob['content'],
      'sections': blob['sections'],
      'citations': blob['citations'],
    });
  }

  Future<http.Response> _get(String url) async {
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse(url),
        headers: {
          'apikey': supabaseAnonKey,
          'Authorization': 'Bearer $supabaseAnonKey',
        },
      );
    } catch (e) {
      throw ApiException('Could not reach the server: $e');
    }

    if (response.statusCode != 200) {
      throw ApiException(
        'Request failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    return response;
  }
}
