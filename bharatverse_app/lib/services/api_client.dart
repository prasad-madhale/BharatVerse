import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/article.dart';
import 'article_cache.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Shown when a request never reaches the server.
const unreachableMessage =
    'Could not reach the server. Check your connection and try again.';

/// What to show a reader when a request fails: the exception's own
/// plain-language message, or a generic one for anything unexpected.
String describeError(Object? error) => error is ApiException
    ? error.message
    : 'Something went wrong. Please try again.';

/// Supabase Storage bucket articles' content JSON lives in -- mirrors the
/// backend's default (see backend/config.py's articles_storage_bucket).
const _articlesBucket = 'articles';

/// Reads articles straight from Supabase's REST (PostgREST) and Storage
/// HTTP APIs using the anon key -- the same credentials and RLS-gated
/// access the FastAPI backend's read endpoints use (see
/// backend/services/article_service.py). This works identically on web,
/// simulator, and a real device on any network, since it never depends on
/// a local dev server being reachable.
///
/// Every article it loads is also saved in the optional [cache]. When the
/// server cannot be reached, reads fall back to what is saved and [offline]
/// says so.
class ApiClient {
  /// Supabase project URL. Override only for tests.
  final String baseUrl;
  final http.Client _client;
  final ArticleCache? _cache;

  /// True while what is on screen came from the device because the server
  /// could not be reached. The next request that succeeds clears it.
  final offline = ValueNotifier<bool>(false);

  ApiClient({
    String? baseUrl,
    http.Client? client,
    ArticleCache? cache,
  })  : baseUrl = baseUrl ?? supabaseUrl,
        _client = client ?? http.Client(),
        _cache = cache;

  Future<Article> getDailyArticle() => _liveOrSaved(
        () async {
          final rows = await _fetchRows('select=*&order=date.desc&limit=1');
          if (rows.isEmpty) {
            throw ApiException('No articles available', statusCode: 404);
          }
          return (await loadArticles(rows)).first;
        },
        () async => (await _cache?.getCachedArticles())?.firstOrNull,
      );

  Future<Article> getArticleById(String id) => _liveOrSaved(
        () async {
          final rows = await _fetchRows('select=*&id=eq.$id&limit=1');
          if (rows.isEmpty) {
            throw ApiException('Article not found', statusCode: 404);
          }
          return (await loadArticles(rows)).first;
        },
        () async => _cache?.getCachedArticle(id),
      );

  Future<List<Article>> getRecentArticles({int limit = 5}) => _liveOrSaved(
        () async => loadArticles(
            await _fetchRows('select=*&order=date.desc&limit=$limit')),
        () => _saved((all) => all.take(limit)),
      );

  /// One page of articles, newest first. The order is total, so pages never
  /// repeat or skip an article.
  Future<List<Article>> listArticles({int page = 0, int limit = 20}) =>
      _liveOrSaved(
        () async => loadArticles(
            await _fetchRows('select=*&order=date.desc,created_at.desc,id.desc'
                '&offset=${page * limit}&limit=$limit')),
        () => _saved((all) => all.skip(page * limit).take(limit)),
      );

  /// Full-text search over title and summary, most relevant first. Calls the
  /// same `search_articles` database function as the backend's
  /// `/articles/search`, so quoted phrases and `-exclusions` work. Not
  /// available offline.
  Future<List<Article>> searchArticles(String query, {int limit = 20}) async {
    final response = await _post('$baseUrl/rest/v1/rpc/search_articles', {
      'search_query': query.trim(),
      'match_limit': limit,
    });
    return loadArticles((jsonDecode(response.body) as List<dynamic>)
        .cast<Map<String, dynamic>>());
  }

  /// Builds full articles from `articles` rows, fetching each one's content,
  /// and saves them for offline reading.
  Future<List<Article>> loadArticles(List<Map<String, dynamic>> rows) async {
    final articles = await Future.wait(rows.map(_loadArticle));
    await _remember(articles);
    return articles;
  }

  /// Notes that [article] was just opened, so it is the last to leave the
  /// offline cache.
  Future<void> markViewed(Article article) => _remember([article]);

  Future<void> _remember(List<Article> articles) async {
    try {
      await _cache?.cacheArticles(articles);
    } catch (_) {
      // A full or unavailable store must not stop anyone reading.
    }
  }

  Future<List<Article>?> _saved(
    Iterable<Article> Function(List<Article> all) pick,
  ) async {
    final all = await _cache?.getCachedArticles();
    return all == null || all.isEmpty ? null : pick(all).toList();
  }

  /// Runs [live]; if the server cannot be reached, answers from [saved]
  /// instead. Only that failure falls back: the server refusing a request is
  /// shown as it is.
  Future<T> _liveOrSaved<T>(
    Future<T> Function() live,
    Future<T?> Function() saved,
  ) async {
    try {
      return await live();
    } on ApiException catch (e) {
      final fallback = e.statusCode == null ? await saved() : null;
      if (fallback == null) {
        rethrow;
      }
      offline.value = true;
      return fallback;
    }
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

  Map<String, String> get _headers => {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $supabaseAnonKey',
      };

  Future<http.Response> _get(String url) =>
      _send(() => _client.get(Uri.parse(url), headers: _headers));

  Future<http.Response> _post(String url, Object body) =>
      _send(() => _client.post(
            Uri.parse(url),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          ));

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request();
    } catch (e) {
      throw ApiException(unreachableMessage);
    }

    if (response.statusCode != 200) {
      throw ApiException(
        'Request failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    offline.value = false;
    return response;
  }
}
