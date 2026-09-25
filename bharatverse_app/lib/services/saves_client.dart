import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'api_client.dart';

/// Reads and writes the signed-in user's saved (bookmarked) articles through
/// Supabase's REST API, with the user's own token so row-level security
/// scopes each call to their rows.
class SavesClient {
  final String baseUrl;
  final http.Client _client;

  SavesClient({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ?? supabaseUrl,
        _client = client ?? http.Client();

  Future<Set<String>> getSavedArticleIds({required String accessToken}) async {
    final response = await _send(
      'GET',
      {'select': 'article_id'},
      accessToken: accessToken,
    );
    return (jsonDecode(response.body) as List<dynamic>)
        .map((row) => (row as Map<String, dynamic>)['article_id'] as String)
        .toSet();
  }

  /// The `articles` rows this user has saved, most recently saved first.
  Future<List<Map<String, dynamic>>> getSavedArticleRows({
    required String accessToken,
    int limit = 20,
  }) async {
    final response = await _send(
      'GET',
      {'select': 'articles(*)', 'order': 'created_at.desc', 'limit': '$limit'},
      accessToken: accessToken,
    );
    return (jsonDecode(response.body) as List<dynamic>)
        .map((row) =>
            (row as Map<String, dynamic>)['articles'] as Map<String, dynamic>)
        .toList();
  }

  /// Idempotent. Uses `ignore-duplicates` rather than `merge-duplicates`: the
  /// table has no UPDATE policy, so row-level security would refuse a merge.
  Future<void> save({
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

  Future<void> unsave({
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
      Uri.parse('$baseUrl/rest/v1/saved_articles')
          .replace(queryParameters: query),
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
      throw ApiException(unreachableMessage);
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
