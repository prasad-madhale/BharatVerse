import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'api_client.dart';

/// Reads and writes the signed-in user's likes straight through Supabase's
/// REST (PostgREST) API. Unlike [ApiClient]'s public reads, every call here
/// carries the *user's* access token: the `likes` table's row-level security
/// (see backend/database/schema.sql) only lets a user see and change their
/// own rows, so the anon key alone would see and change nothing.
class LikesClient {
  /// Supabase project URL. Override only for tests.
  final String baseUrl;
  final http.Client _client;

  LikesClient({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ?? supabaseUrl,
        _client = client ?? http.Client();

  /// Ids of the articles the token's user has liked.
  Future<Set<String>> getLikedArticleIds({required String accessToken}) async {
    final response = await _send(
      'GET',
      {'select': 'article_id'},
      accessToken: accessToken,
    );
    return (jsonDecode(response.body) as List<dynamic>)
        .map((row) => (row as Map<String, dynamic>)['article_id'] as String)
        .toSet();
  }

  /// Records a like. Idempotent: liking twice is not an error. The table has a
  /// unique (user_id, article_id) index, and `ignore-duplicates` (ON CONFLICT DO
  /// NOTHING) skips the second insert. It is not `merge-duplicates` because the
  /// table has no UPDATE policy, so row-level security would refuse the update
  /// that merging performs on an existing row.
  Future<void> like({
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

  /// Removes a like. Idempotent. Row-level security limits the delete to the
  /// token user's own rows.
  Future<void> unlike({
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
      Uri.parse('$baseUrl/rest/v1/likes').replace(queryParameters: query),
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
      throw ApiException('Could not reach the server: $e');
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
