import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/screens/app_shell.dart';
import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/screens/library_screen.dart';
import 'package:bharatverse_app/screens/search_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/services/reading_history.dart';
import 'package:bharatverse_app/state/auth_state.dart';

import '../support/article_fixtures.dart';
import '../support/like_fixtures.dart'
    show stubAuthClient, stubLikesClient, stubSavesClient, withLikeProviders;

Future<Widget> _wrap(ApiClient apiClient, {ReadingHistory? history}) async =>
    ChangeNotifierProvider<ReadingHistory>.value(
      value: history ?? ReadingHistory(await SharedPreferences.getInstance()),
      child: withLikeProviders(
        authState: AuthState(authClient: stubAuthClient()),
        likesClient: stubLikesClient(),
        savesClient: stubSavesClient(),
        child: MaterialApp(home: AppShell(apiClient: apiClient)),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('starts on the Today tab, showing the daily article',
      (tester) async {
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));

    await tester.pumpWidget(await _wrap(apiClient));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('switching to the Library tab shows LibraryScreen',
      (tester) async {
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));

    await tester.pumpWidget(await _wrap(apiClient));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  testWidgets('the search button opens SearchScreen', (tester) async {
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));

    await tester.pumpWidget(await _wrap(apiClient));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
  });

  group('continue-reading bar', () {
    testWidgets('is absent with nothing in reading history', (tester) async {
      final apiClient =
          ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));

      await tester.pumpWidget(await _wrap(apiClient));
      await tester.pumpAndSettle();

      expect(find.text('Continue reading · 13 min read'), findsNothing);
    });

    testWidgets('shows the most recently read article and reopens it on tap',
        (tester) async {
      final rows = {
        'art_1': sampleArticleRow(id: 'art_1', title: 'Article One'),
        'art_2': sampleArticleRow(id: 'art_2', title: 'Article Two'),
      };
      final apiClient = ApiClient(
        client: MockClient((request) async {
          if (request.url.path.contains('/storage/')) {
            return http.Response(jsonEncode(sampleArticleContent()), 200);
          }
          final id = request.url.queryParameters['id']?.replaceFirst('eq.', '');
          return http.Response(
              jsonEncode(id == null ? rows.values.toList() : [rows[id]]), 200);
        }),
      );
      final history = ReadingHistory(await SharedPreferences.getInstance());
      await history.recordOpened('art_1');
      await history.recordOpened('art_2');

      await tester.pumpWidget(await _wrap(apiClient, history: history));
      await tester.pumpAndSettle();

      expect(find.text('Continue reading · 13 min read'), findsOneWidget);

      await tester.tap(find.text('Continue reading · 13 min read'));
      await tester.pumpAndSettle();

      expect(find.byType(ArticleDetailScreen), findsOneWidget);
    });
  });
}
