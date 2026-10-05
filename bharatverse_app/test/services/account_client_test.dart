import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bharatverse_app/config.dart';
import 'package:bharatverse_app/services/account_client.dart';
import 'package:bharatverse_app/services/api_client.dart';

void main() {
  group('AccountClient.deleteAccount', () {
    test('calls delete_my_account with the user\'s own token', () async {
      final seen = <http.Request>[];
      final client = AccountClient(
        baseUrl: 'https://example.supabase.co',
        client: MockClient((request) async {
          seen.add(request);
          return http.Response('', 204);
        }),
      );

      await client.deleteAccount(accessToken: 'user-token');

      final request = seen.single;
      expect(request.method, 'POST');
      expect(request.url.toString(),
          'https://example.supabase.co/rest/v1/rpc/delete_my_account');
      expect(request.headers['Authorization'], 'Bearer user-token');
      expect(request.headers['apikey'], supabaseAnonKey);
    });

    test('a refusal throws with its status', () async {
      final client = AccountClient(
          client: MockClient((_) async => http.Response('denied', 401)));

      expect(
        () => client.deleteAccount(accessToken: 'user-token'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('an unreachable server throws the unreachable message', () async {
      final client = AccountClient(
          client: MockClient((_) async => throw http.ClientException('down')));

      expect(
        () => client.deleteAccount(accessToken: 'user-token'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', unreachableMessage)),
      );
    });
  });
}
