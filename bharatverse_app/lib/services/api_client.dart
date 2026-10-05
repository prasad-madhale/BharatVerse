import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/article.dart';
import 'article_cache.dart';

/// One era with a thumbnail for Search's "Browse by era" grid.
typedef EraSummary = ({String era, String? imageUrl});

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

  /// Saves one image where the app's image widgets look for it first.
  final Future<void> Function(String url) _downloadImage;

  ApiClient({
    String? baseUrl,
    http.Client? client,
    ArticleCache? cache,
    Future<void> Function(String url)? downloadImage,
  })  : baseUrl = baseUrl ?? supabaseUrl,
        _client = client ?? http.Client(),
        _cache = cache,
        _downloadImage =
            downloadImage ?? ((url) => DefaultCacheManager().downloadFile(url));

  Future<Article> getDailyArticle() => _liveOrSaved(
        () async {
          final rows = await _fetchRows('select=*&order=date.desc&limit=1');
          final articles = await loadArticles(rows);
          if (articles.isEmpty) {
            throw ApiException('No articles available', statusCode: 404);
          }
          return articles.first;
        },
        () async => (await _cache?.getCachedArticles())?.firstOrNull,
      );

  Future<Article> getArticleById(String id) => _liveOrSaved(
        () async {
          final rows = await _fetchRows('select=*&id=eq.$id&limit=1');
          final articles = await loadArticles(rows);
          if (articles.isEmpty) {
            throw ApiException('Article not found', statusCode: 404);
          }
          return articles.first;
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

  /// Saves the last [days] days of articles on the device, and at least the
  /// [days] most recent when that week had fewer, so they read offline
  /// (requirement 8.3). Run on every load, it also refreshes the saved copies
  /// (8.5). With [withImages], their pictures are saved too. Returns what was
  /// saved; throws [ApiException] when the server cannot be reached.
  Future<List<Article>> saveRecentForOffline(
      {int days = 7, bool withImages = false, DateTime? now}) async {
    final today = now ?? DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: days - 1));
    final rows = await _fetchRows('select=*&order=date.desc&limit=50');
    final articles = await loadArticles([
      for (final (index, row) in rows.indexed)
        if (index < days ||
            !DateTime.parse(row['date'] as String).isBefore(cutoff))
          row,
    ]);
    if (withImages) {
      for (final image in articles.expand((a) => a.images)) {
        try {
          await _downloadImage(image.url);
        } catch (_) {
          // One picture that will not download must not stop the rest.
        }
      }
    }
    return articles;
  }

  /// The distinct, non-empty eras among the most recent [limit] articles,
  /// newest first, each paired with one representative image -- for
  /// Search's "Browse by era" grid. A lightweight metadata-only fetch (no
  /// content or image download), since a card only needs the era label and
  /// a thumbnail URL.
  Future<List<EraSummary>> getEras({int limit = 100}) => _liveOrSaved(
        () async {
          final rows = await _fetchRows(
              'select=era,image_url&order=date.desc&limit=$limit');
          return _distinctEras(rows.map((row) => (
                era: row['era'] as String? ?? '',
                imageUrl: row['image_url'] as String?,
              )));
        },
        () async {
          final all = await _cache?.getCachedArticles();
          if (all == null) return null;
          final eras =
              _distinctEras(all.map((a) => (era: a.era, imageUrl: a.imageUrl)));
          return eras.isEmpty ? null : eras;
        },
      );

  List<EraSummary> _distinctEras(Iterable<EraSummary> candidates) {
    final seen = <String>{};
    return [
      for (final c in candidates)
        if (c.era.isNotEmpty && seen.add(c.era)) c,
    ];
  }

  /// Full-text search over title, tags and summary, most relevant first. Calls the
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

  /// The titles and tags that start with [prefix], the ones more articles
  /// share first, from the same `autocomplete_suggestions` database function as
  /// the backend's `/articles/search/autocomplete`. Blank text asks nothing.
  /// Not available offline.
  Future<List<String>> getAutocompleteSuggestions(String prefix,
      {int limit = 10}) async {
    final typed = prefix.trim();
    if (typed.isEmpty) {
      return [];
    }
    final response =
        await _post('$baseUrl/rest/v1/rpc/autocomplete_suggestions', {
      'prefix': typed,
      'match_limit': limit,
    });
    return (jsonDecode(response.body) as List<dynamic>)
        .map((row) => (row as Map<String, dynamic>)['term'] as String)
        .toList();
  }

  /// Builds full articles from `articles` rows, fetching each one's content,
  /// and saves them for offline reading. A row whose content the server will
  /// not give (a missing or unreadable file) is left out, so one bad article
  /// never hides the rest; losing the connection still fails the whole load.
  Future<List<Article>> loadArticles(List<Map<String, dynamic>> rows) async {
    final articles =
        (await Future.wait(rows.map(_loadArticleIfServed))).nonNulls.toList();
    await _remember(articles);
    return articles;
  }

  Future<Article?> _loadArticleIfServed(Map<String, dynamic> row) async {
    try {
      return await _loadArticle(row);
    } on ApiException catch (e) {
      if (e.statusCode == null) rethrow;
    } on FormatException {
      // Content that is not JSON: leave the article out like a missing file.
    }
    return null;
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
      'images': blob['images'],
    });
  }

  /// Files a reader's report of a problem with [articleId]: [reason] is
  /// `factual`, `image`, `offensive` or `other`. Signed in, it is filed under
  /// [userId] with their [accessToken]; signed out, anonymously. Reports are
  /// write-only: the owner reads them in the Supabase dashboard.
  Future<void> reportArticle({
    required String articleId,
    required String reason,
    String? note,
    String? userId,
    String? accessToken,
  }) async {
    final trimmed = note?.trim() ?? '';
    await _post(
      '$baseUrl/rest/v1/article_reports',
      {
        'article_id': articleId,
        'reason': reason,
        if (trimmed.isNotEmpty) 'note': trimmed,
        if (userId != null) 'user_id': userId,
      },
      accessToken: accessToken,
      headers: const {'Prefer': 'return=minimal'},
    );
  }

  Map<String, String> get _headers => {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $supabaseAnonKey',
      };

  Future<http.Response> _get(String url) =>
      _send(() => _client.get(Uri.parse(url), headers: _headers));

  /// Signed in, [accessToken] replaces the public key, so row-level security
  /// sees the reader.
  Future<http.Response> _post(String url, Object body,
          {String? accessToken, Map<String, String> headers = const {}}) =>
      _send(() => _client.post(
            Uri.parse(url),
            headers: {
              ..._headers,
              if (accessToken != null) 'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
              ...headers,
            },
            body: jsonEncode(body),
          ));

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request();
    } catch (e) {
      throw ApiException(unreachableMessage);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Request failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    offline.value = false;
    return response;
  }
}
