import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/screens/search_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/app_button.dart';
import 'package:bharatverse_app/widgets/article_card.dart';

import '../support/article_fixtures.dart';
import '../support/highlight_finder.dart';
import '../support/like_fixtures.dart';
import '../support/layout_fixtures.dart';

void main() {
  late List<http.Request> requests;

  Future<void> pumpSearch(
    WidgetTester tester, {
    List<Map<String, dynamic>> Function()? rows,
    MockClient? client,
  }) async {
    requests = [];
    final apiClient = ApiClient(
      client: client ??
          articlesMockClient(rows ?? () => [sampleArticleRow()],
              onRequest: requests.add),
    );
    await tester.pumpWidget(withLikeProviders(
      authState: AuthState(authClient: stubAuthClient()),
      likesClient: stubLikesClient(),
      child: MaterialApp(home: SearchScreen(apiClient: apiClient)),
    ));
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.tap(find.widgetWithText(AppButton, 'Search'));
    await tester.pumpAndSettle();
  }

  group('SearchScreen', () {
    testWidgets('starts with a prompt and sends nothing', (tester) async {
      await pumpSearch(tester);

      expect(find.text('SEARCH THE ARCHIVE'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets(
        'lists the matches with a count and hands the terms to the cards',
        (tester) async {
      await pumpSearch(tester);

      await search(tester, 'mauryan "Bay of Bengal" -chola');

      expect(find.text('1 result'), findsOneWidget);
      expect(tester.widget<ArticleCard>(find.byType(ArticleCard)).highlight,
          ['mauryan', 'Bay of Bengal']);
    });

    testWidgets('highlights the matched terms in each result', (tester) async {
      await pumpSearch(tester);

      await search(tester, 'mauryan');

      expect(marked(tester), ['MAURYAN', 'Mauryan']); // title, then summary
    });

    testWidgets('sends the trimmed query as a websearch filter, newest first',
        (tester) async {
      await pumpSearch(tester);

      await search(tester, '  Ashoka dhamma  ');

      final query = requests.single.url.queryParameters;
      expect(query['search_vector'], 'wfts(english).Ashoka dhamma');
      expect(query['order'], 'date.desc');
    });

    testWidgets('searches when the keyboard search action is pressed',
        (tester) async {
      await pumpSearch(tester);

      await tester.enterText(find.byType(TextField), 'Ashoka');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(find.byType(ArticleCard), findsOneWidget);
    });

    testWidgets('ignores a blank query', (tester) async {
      await pumpSearch(tester);

      await search(tester, '   ');

      expect(requests, isEmpty);
      expect(find.text('SEARCH THE ARCHIVE'), findsOneWidget);
    });

    testWidgets('says so, and suggests another search, when nothing matches',
        (tester) async {
      await pumpSearch(tester, rows: () => []);

      await search(tester, 'zzz');

      expect(find.text('NO RESULTS'), findsOneWidget);
      expect(find.textContaining('Nothing matched "zzz"'), findsOneWidget);
      expect(find.textContaining('Try a different spelling'), findsOneWidget);
    });

    testWidgets('shows a failure with a retry that repeats the submitted query',
        (tester) async {
      var failNext = true;
      final client = MockClient((request) async {
        if (request.url.path.contains('/storage/')) {
          return http.Response(jsonEncode(sampleArticleContent()), 200);
        }
        requests.add(request);
        if (failNext) {
          failNext = false;
          return http.Response('boom', 500);
        }
        return http.Response(jsonEncode([sampleArticleRow()]), 200);
      });
      await pumpSearch(tester, client: client);

      await search(tester, 'ashoka');
      expect(find.text('SEARCH FAILED'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'edited since');
      await tester.tap(find.widgetWithText(AppButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(requests.map((r) => r.url.queryParameters['search_vector']),
          ['wfts(english).ashoka', 'wfts(english).ashoka']);
      expect(find.byType(ArticleCard), findsOneWidget);
    });

    testWidgets('opens the article when a result is tapped', (tester) async {
      await pumpSearch(tester);
      await search(tester, 'mauryan');

      await tester.tap(find.byType(ArticleCard));
      await tester.pumpAndSettle();

      expect(find.byType(ArticleDetailScreen), findsOneWidget);
    });
  });

  testWidgets('keeps the form in a readable column on a wide screen',
      (tester) async {
    useWideScreen(tester);
    await pumpSearch(tester);

    expect(tester.getSize(find.byType(TextField)).width, 720 - 2 * 16);
  });
}
