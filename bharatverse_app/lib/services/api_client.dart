import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/article.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiClient {
  /// Defaults to the Android emulator's alias for the host machine's
  /// localhost (10.0.2.2), since that's the most common local dev target.
  /// Override for iOS simulator/desktop/web (use 'http://localhost:8000/api/v1')
  /// or a real device/deployed backend (LAN IP or public URL).
  final String baseUrl;
  final http.Client _client;

  ApiClient({
    this.baseUrl = 'http://10.0.2.2:8000/api/v1',
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<Article> getDailyArticle() => _getArticle('$baseUrl/articles/daily');

  Future<Article> getArticleById(String id) => _getArticle('$baseUrl/articles/$id');

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
