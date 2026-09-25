import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bharatverse_app/models/article.dart';
import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/screens/search_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/app_button.dart';
import 'package:bharatverse_app/widgets/article_card.dart';
import 'package:bharatverse_app/widgets/suggestion_tile.dart';

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
      savesClient: stubSavesClient(),
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

      // the title, the summary, then the tag the term is also in
      expect(marked(tester), ['MAURYAN', 'Mauryan', 'mauryan']);
    });

    testWidgets('sends the trimmed query to the ranked search', (tester) async {
      await pumpSearch(tester);

      await search(tester, '  Ashoka dhamma  ');

      final request = requests.single;
      expect(request.url.path, '/rest/v1/rpc/search_articles');
      expect(jsonDecode(request.body)['search_query'], 'Ashoka dhamma');
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

      expect(requests.map((r) => jsonDecode(r.body)['search_query']),
          ['ashoka', 'ashoka']);
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

  group('SearchScreen suggestions', () {
    bool isSuggestionRequest(http.Request r) =>
        r.url.path.endsWith('/rpc/autocomplete_suggestions');

    List<String> asked() => [
          for (final r in requests.where(isSuggestionRequest))
            jsonDecode(r.body)['prefix'] as String
        ];

    MockClient client(Future<List<String>?> Function(String prefix) suggest) =>
        searchMockClient(
            suggest: suggest, onRequest: (request) => requests.add(request));

    /// Types [text], lets the debounce pass and delivers the answer.
    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
    }

    Finder tile(String term) => find.widgetWithText(SuggestionTile, term);

    testWidgets('asks once, after typing pauses, for the text typed so far',
        (tester) async {
      await pumpSearch(tester, client: client((_) async => ['Mauryan Empire']));

      await tester.enterText(find.byType(TextField), 'm');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'mau');
      await tester.pump(const Duration(milliseconds: 199));

      expect(asked(), isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(asked(), ['mau']);
    });

    testWidgets('shows them in place of the prompt with the typed start marked',
        (tester) async {
      await pumpSearch(tester,
          client: client((_) async => ['Mauryan Empire', 'Maurya']));

      await type(tester, 'mau');

      expect(find.byType(SuggestionTile), findsNWidgets(2));
      expect(marked(tester), ['Mau', 'Mau']);
      expect(find.text('SEARCH THE ARCHIVE'), findsNothing);
    });

    testWidgets('tells a screen reader how many suggestions appeared for what',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpSearch(tester,
          client: client((prefix) async => prefix == 'ma'
              ? ['Maritime History', 'Mauryan Empire']
              : ['Ma']));

      await type(tester, 'ma');
      expect(find.bySemanticsLabel('2 suggestions for ma'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('2 suggestions for ma')),
          matchesSemantics(label: '2 suggestions for ma', isLiveRegion: true));

      await type(tester, 'm');
      expect(find.bySemanticsLabel('1 suggestion for m'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('reads each suggestion as a button', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpSearch(tester, client: client((_) async => ['Ashoka']));

      await type(tester, 'ash');

      expect(
          tester.getSemantics(find.byType(SuggestionTile)),
          matchesSemantics(
              label: 'Ashoka',
              isButton: true,
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true));
      semantics.dispose();
    });

    testWidgets('searches for a suggestion when it is tapped', (tester) async {
      await pumpSearch(tester, client: client((_) async => ['Mauryan Empire']));
      await type(tester, 'mau');

      await tester.tap(tile('Mauryan Empire'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Mauryan Empire');
      final search = requests.last;
      expect(search.url.path, '/rest/v1/rpc/search_articles');
      expect(jsonDecode(search.body)['search_query'], 'Mauryan Empire');
      expect(find.byType(ArticleCard), findsOneWidget);
      expect(find.byType(SuggestionTile), findsNothing);
      expect(tester.testTextInput.hasAnyClients, isFalse);
    });

    testWidgets('a search retried after a suggestion repeats that suggestion',
        (tester) async {
      var failNext = true;
      await pumpSearch(
        tester,
        client: MockClient((request) async {
          if (request.url.path.contains('/storage/')) {
            return http.Response(jsonEncode(sampleArticleContent()), 200);
          }
          if (isSuggestionRequest(request)) {
            return http.Response(
                jsonEncode([
                  {'term': 'Mauryan Empire'}
                ]),
                200);
          }
          requests.add(request);
          if (failNext) {
            failNext = false;
            return http.Response('boom', 500);
          }
          return http.Response(jsonEncode([sampleArticleRow()]), 200);
        }),
      );
      await type(tester, 'mau');

      await tester.tap(tile('Mauryan Empire'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(requests.map((r) => jsonDecode(r.body)['search_query']),
          ['Mauryan Empire', 'Mauryan Empire']);
      expect(find.byType(ArticleCard), findsOneWidget);
    });

    testWidgets('submitting the search hides them and drops a late answer',
        (tester) async {
      final answer = Completer<List<String>?>();
      await pumpSearch(tester, client: client((_) => answer.future));
      await tester.enterText(find.byType(TextField), 'ashoka');
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.widgetWithText(AppButton, 'Search'));
      answer.complete(['Ashoka']);
      await tester.pumpAndSettle();

      expect(find.byType(SuggestionTile), findsNothing);
      expect(find.byType(ArticleCard), findsOneWidget);
    });

    testWidgets('the keyboard search action hides them too', (tester) async {
      await pumpSearch(tester, client: client((_) async => ['Ashoka']));
      await type(tester, 'ash');

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byType(SuggestionTile), findsNothing);
      expect(find.byType(ArticleCard), findsOneWidget);
    });

    testWidgets('an answer for older text does not replace a newer one',
        (tester) async {
      final answers = <String, Completer<List<String>?>>{
        'ma': Completer(),
        'mau': Completer(),
      };
      await pumpSearch(tester,
          client: client((prefix) => answers[prefix]!.future));
      await type(tester, 'ma');
      await type(tester, 'mau');

      answers['mau']!.complete(['Mauryan Empire']);
      await tester.pump();
      answers['ma']!.complete(['Maritime History']);
      await tester.pump();

      expect(tile('Mauryan Empire'), findsOneWidget);
      expect(tile('Maritime History'), findsNothing);
    });

    testWidgets('emptying the field clears them at once', (tester) async {
      await pumpSearch(tester,
          client: client((_) async => ['Maritime History']));
      await type(tester, 'ma');
      expect(find.byType(SuggestionTile), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.byType(SuggestionTile), findsNothing);
      expect(find.text('SEARCH THE ARCHIVE'), findsOneWidget);
    });

    testWidgets('emptying the field drops the request still waiting',
        (tester) async {
      final answer = Completer<List<String>?>();
      await pumpSearch(tester, client: client((_) => answer.future));
      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(find.byType(TextField), '');
      answer.complete(['Maritime History']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SuggestionTile), findsNothing);
      expect(asked(), ['ma']);
    });

    testWidgets(
        'marks what the suggestions were asked for, not what came after',
        (tester) async {
      final answer = Completer<List<String>?>();
      await pumpSearch(tester, client: client((_) => answer.future));
      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump(const Duration(milliseconds: 200));

      // more is typed before the answer for "ma" arrives
      await tester.enterText(find.byType(TextField), 'mar');
      answer.complete(['Maritime History']);
      await tester.pump();

      expect(marked(tester), ['Ma']);
    });

    testWidgets('blank text asks for nothing', (tester) async {
      await pumpSearch(tester, client: client((_) async => ['Everything']));

      await type(tester, '   ');
      await tester.pump(const Duration(milliseconds: 300));

      expect(requests, isEmpty);
      expect(find.byType(SuggestionTile), findsNothing);
    });

    testWidgets('shows nothing, and no error, when suggestions cannot be had',
        (tester) async {
      await pumpSearch(tester, client: client((_) async => null));

      await type(tester, 'ash');

      expect(find.byType(SuggestionTile), findsNothing);
      expect(find.text('SEARCH THE ARCHIVE'), findsOneWidget);
      expect(find.textContaining('went wrong'), findsNothing);

      await tester.tap(find.widgetWithText(AppButton, 'Search'));
      await tester.pumpAndSettle();

      expect(find.byType(ArticleCard), findsOneWidget);
    });

    testWidgets('shows nothing when the connection fails', (tester) async {
      await pumpSearch(
        tester,
        client: MockClient((request) async {
          if (isSuggestionRequest(request)) {
            throw http.ClientException('offline');
          }
          return http.Response(jsonEncode([sampleArticleRow()]), 200);
        }),
      );

      await type(tester, 'ash');

      expect(tester.takeException(), isNull);
      expect(find.byType(SuggestionTile), findsNothing);
    });

    testWidgets(
        'keeps the results, their place and no spinner while suggestions come and go',
        (tester) async {
      await pumpSearch(
        tester,
        client: searchMockClient(
          rows: () => [
            for (var n = 0; n < 8; n++)
              sampleArticleRow(id: 'art_$n', title: 'Article $n')
          ],
          suggest: (_) async => ['Ashoka'],
          onRequest: (request) => requests.add(request),
        ),
      );
      await search(tester, 'mauryan');
      final scrollable = find.descendant(
          of: find.byType(FutureBuilder<List<Article>>),
          matching: find.byType(Scrollable));
      await tester.drag(find.byType(ArticleCard).first, const Offset(0, -250));
      await tester.pumpAndSettle();
      final scrolledTo =
          tester.state<ScrollableState>(scrollable).position.pixels;
      expect(scrolledTo, greaterThan(0));

      await type(tester, 'ash');
      expect(find.byType(SuggestionTile), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.state<ScrollableState>(scrollable).position.pixels,
          scrolledTo);
    });

    testWidgets('suggests in any script and marks what was typed',
        (tester) async {
      await pumpSearch(tester,
          client: client((_) async => ['अशोक', 'अशोक स्तंभ']));

      await type(tester, 'अश');

      expect(tile('अशोक'), findsOneWidget);
      expect(tile('अशोक स्तंभ'), findsOneWidget);
      expect(marked(tester), ['अश', 'अश']);
    });

    testWidgets('shows nothing when the answer is not what was expected',
        (tester) async {
      await pumpSearch(
        tester,
        client: MockClient((request) async => isSuggestionRequest(request)
            ? http.Response('not json', 200)
            : http.Response(jsonEncode([sampleArticleRow()]), 200)),
      );

      await type(tester, 'ash');

      expect(tester.takeException(), isNull);
      expect(find.byType(SuggestionTile), findsNothing);
    });

    testWidgets('keeps the results while nothing is suggested', (tester) async {
      await pumpSearch(tester, client: client((_) async => []));
      await search(tester, 'mauryan');

      await type(tester, 'mauryan e');

      expect(find.byType(ArticleCard), findsOneWidget);
      expect(find.text('1 result'), findsOneWidget);
    });

    testWidgets('covers earlier results while showing and restores them after',
        (tester) async {
      await pumpSearch(tester, client: client((_) async => ['Ashoka']));
      await search(tester, 'mauryan');

      await type(tester, 'ash');

      expect(find.byType(SuggestionTile), findsOneWidget);
      expect(find.byType(ArticleCard), findsNothing);

      await type(tester, '');

      expect(find.byType(SuggestionTile), findsNothing);
      expect(find.byType(ArticleCard), findsOneWidget);
    });

    testWidgets('does nothing more once the screen is gone', (tester) async {
      final answer = Completer<List<String>?>();
      await pumpSearch(tester, client: client((_) => answer.future));
      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 300));

      expect(asked(), isEmpty);

      // and an answer that lands after the screen has gone is dropped quietly
      await pumpSearch(tester, client: client((_) => answer.future));
      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      answer.complete(['Maritime History']);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the rows in a readable column on a wide screen',
        (tester) async {
      useWideScreen(tester);
      await pumpSearch(tester, client: client((_) async => ['Mauryan Empire']));

      await type(tester, 'mau');

      expect(tester.getSize(find.byType(SuggestionTile)).width, 720 - 2 * 16);
    });
  });

  testWidgets('keeps the form in a readable column on a wide screen',
      (tester) async {
    useWideScreen(tester);
    await pumpSearch(tester);

    expect(tester.getSize(find.byType(TextField)).width, 720 - 2 * 16);
  });

  testWidgets('hides an unexpected error behind a generic message',
      (tester) async {
    await pumpSearch(tester,
        client: MockClient((_) async => http.Response('not json', 200)));

    await search(tester, 'ashoka');

    expect(find.text('SEARCH FAILED'), findsOneWidget);
    expect(
        find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.textContaining('FormatException'), findsNothing);
  });
}
