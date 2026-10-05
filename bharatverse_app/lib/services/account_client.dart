import 'package:http/http.dart' as http;

import '../config.dart';
import 'api_client.dart';

/// The signed-in user's account itself, through Supabase's REST API with
/// their own token.
class AccountClient {
  final String baseUrl;
  final http.Client _client;

  AccountClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? supabaseUrl,
        _client = client ?? http.Client();

  /// Deletes the account with its likes and saves (`delete_my_account` in
  /// schema.sql).
  Future<void> deleteAccount({required String accessToken}) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$baseUrl/rest/v1/rpc/delete_my_account'),
        headers: {
          'apikey': supabaseAnonKey,
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: '{}',
      );
    } catch (_) {
      throw ApiException(unreachableMessage);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Request failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
  }
}
