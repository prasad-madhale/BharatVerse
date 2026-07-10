import 'dart:convert';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

import '../models/article.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Android emulator's alias for the host machine's localhost -- only
/// resolves from inside the emulator, not anywhere else.
const _androidEmulatorHostUrl = 'http://10.0.2.2:8000/api/v1';

/// Real localhost, needed on web/desktop/iOS simulator since those run
/// directly on the host machine (or in the host's browser) rather than
/// in a separate virtualized network namespace like the Android emulator.
const _localhostUrl = 'http://localhost:8000/api/v1';

/// Picks the local dev backend URL per-platform. Uses `defaultTargetPlatform`
/// (not `dart:io`'s `Platform`, which can't be imported in web builds) so
/// this one function works unconditionally across web/mobile/desktop.
String _defaultBaseUrl() {
  if (kIsWeb) return _localhostUrl;
  if (defaultTargetPlatform == TargetPlatform.android) {
    return _androidEmulatorHostUrl;
  }
  return _localhostUrl;
}

class ApiClient {
  /// Defaults per-platform to the local dev backend. Override for a real
  /// device or deployed backend (LAN IP or public URL).
  final String baseUrl;
  final http.Client _client;

  ApiClient({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ?? _defaultBaseUrl(),
        _client = client ?? http.Client();

  Future<Article> getDailyArticle() => _getArticle('$baseUrl/articles/daily');

  Future<Article> getArticleById(String id) =>
      _getArticle('$baseUrl/articles/$id');

  Future<Article> _getArticle(String url) async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse(url));
    } catch (e) {
      throw ApiException('Could not reach the server: $e');
    }

    if (response.statusCode == 404) {
      throw ApiException('Article not found', statusCode: 404);
    }
    if (response.statusCode != 200) {
      throw ApiException(
        'Request failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    return Article.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
