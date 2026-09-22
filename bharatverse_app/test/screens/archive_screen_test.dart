import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bharatverse_app/screens/archive_screen.dart';
import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/app_button.dart';
import 'package:bharatverse_app/widgets/article_card.dart';

import '../support/article_fixtures.dart';
import '../support/like_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bharatverse_app/services/article_cache.dart';

/// Rows for articles [from] down to 1, newest first ('Article 45' ... 'Article 1').
List<Map<String, dynamic>> rowsFrom(int from) => [
      for (var n = from; n >= 1; n--)
        sampleArticleRow(
            id: 'art_${n.toString().padLeft(3, '0')}', title: 'Article $n'),
    ];

void main() {
  late List<http.Request> requests;

  /// A client that serves [everything] a page at a time, like PostgREST does
  /// for offset and limit. [answer] can override a page (return null to serve
  /// it normally).
  MockClient pagedClient(
    List<Map<String, dynamic>> everything, {
    http.Response? Function(int offset)? answer,
  }) =>
      MockClient((request) async {
        if (request.url.path.contains('/storage/')) {
          return http.Response(jsonEncode(sampleArticleContent()), 200);
        }
        requests.add(request);
        final offset = int.parse(request.url.queryParameters['offset']!);
        final limit = int.parse(request.url.queryParameters['limit']!);
        final override = answer?.call(offset);
        if (override != null) {
          return override;
        }
        final end = (offset + limit).clamp(0, everything.length);
        final page = offset >= everything.length
            ? <Map<String, dynamic>>[]
            : everything.sublist(offset, end);
        return http.Response(jsonEncode(page), 200);
      });

  Future<void> pumpArchive(WidgetTester tester, MockClient client) async {
    await tester.pumpWidget(withLikeProviders(
      authState: AuthState(authClient: stubAuthClient()),
      likesClient: stubLikesClient(),
      child: MaterialApp(
        home: ArchiveScreen(apiClient: ApiClient(client: client)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
  }

  setUp(() => requests = []);

  group('ArchiveScreen', () {
    testWidgets('lists the first page newest first, with a byline on each row',
        (tester) async {
      await pumpArchive(tester, pagedClient(rowsFrom(45)));

      final query = requests.single.url.queryParameters;
      expect(query['offset'], '0');
      expect(query['limit'], '20');
      expect(query['order'], 'date.desc,created_at.desc,id.desc');
      expect(find.text('ARCHIVE'), findsOneWidget);
      expect(find.text('ARTICLE 45'), findsOneWidget);
      expect(find.text('2026-07-03 · 13 min read'), findsWidgets);
    });

    testWidgets('loads further pages as the reader scrolls, until the end',
        (tester) async {
      await pumpArchive(tester, pagedClient(rowsFrom(45)));

      await scrollToEnd(tester);
      await scrollToEnd(tester);
      await scrollToEnd(tester);

      expect(requests.map((r) => r.url.queryParameters['offset']),
          ['0', '20', '40']);
      expect(find.text('That is every article so far.'), findsOneWidget);
      expect(find.text('ARTICLE 1'), findsOneWidget);
    });

    testWidgets('asks for a page only once while it is still loading',
        (tester) async {
      final gate = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.url.path.contains('/storage/')) {
          return http.Response(jsonEncode(sampleArticleContent()), 200);
        }
        requests.add(request);
        final offset = int.parse(request.url.queryParameters['offset']!);
        if (offset == 20) {
          return gate.future;
        }
        return http.Response(jsonEncode(rowsFrom(45).sublist(0, 20)), 200);
      });
      await pumpArchive(tester, client);

      await tester.drag(find.byType(ListView), const Offset(0, -20000));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        // Scroll back and forth while the second page is still on its way.
        await tester.drag(find.byType(ListView), const Offset(0, 80));
        await tester.pump();
        await tester.drag(find.byType(ListView), const Offset(0, -80));
        await tester.pump();
      }

      expect(requests.where((r) => r.url.queryParameters['offset'] == '20'),
          hasLength(1));
      gate.complete(http.Response(jsonEncode(rowsFrom(25)), 200));
      await tester.pumpAndSettle();
    });

    testWidgets('keeps loading until a tall window is full', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 6000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpArchive(tester, pagedClient(rowsFrom(45)));

      expect(requests.map((r) => r.url.queryParameters['offset']),
          ['0', '20', '40']);
      expect(find.text('That is every article so far.'), findsOneWidget);
    });

    testWidgets('never lists an article twice when a new one shifts the pages',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 9000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final first = rowsFrom(30).sublist(0, 20); // Article 30 ... 11
      final second = rowsFrom(11); // starts again at Article 11
      final client = pagedClient([], answer: (offset) {
        final page = offset == 0 ? first : second;
        return http.Response(jsonEncode(page), 200);
      });

      await pumpArchive(tester, client);

      expect(find.text('ARTICLE 11'), findsOneWidget);
      expect(find.byType(ArticleCard), findsNWidgets(30));
    });

    testWidgets('says so when there are no articles', (tester) async {
      await pumpArchive(tester, pagedClient([]));

      expect(find.text('NO ARTICLES YET'), findsOneWidget);
    });

    testWidgets('shows a failure with a retry when the first page fails',
        (tester) async {
      var fail = true;
      await pumpArchive(
        tester,
        pagedClient(rowsFrom(3), answer: (_) {
          if (!fail) return null;
          fail = false;
          return http.Response('boom', 500);
        }),
      );
      expect(find.text('COULD NOT LOAD ARTICLES'), findsOneWidget);
      expect(find.text('Request failed (500)'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text('ARTICLE 3'), findsOneWidget);
    });

    testWidgets('keeps what it has and offers a retry when a later page fails',
        (tester) async {
      var failSecondPage = true;
      await pumpArchive(
        tester,
        pagedClient(rowsFrom(45), answer: (offset) {
          if (offset != 20 || !failSecondPage) return null;
          failSecondPage = false;
          return http.Response('boom', 500);
        }),
      );

      await scrollToEnd(tester);
      expect(find.text('Request failed (500)'), findsOneWidget);
      expect(find.byType(ArticleCard), findsWidgets);

      await tester.tap(find.widgetWithText(AppButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Request failed (500)'), findsNothing);
      expect(requests.map((r) => r.url.queryParameters['offset']).toList(),
          containsAllInOrder(['0', '20', '20']));
    });

    testWidgets('opens an article when it is tapped', (tester) async {
      await pumpArchive(tester, pagedClient(rowsFrom(3)));

      await tester.tap(find.byType(ArticleCard).first);
      await tester.pumpAndSettle();

      expect(find.byType(ArticleDetailScreen), findsOneWidget);
    });
  });

  testWidgets('shows the saved articles with a notice when offline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cache = ArticleCache(await SharedPreferences.getInstance());
    await cache.cacheArticles([
      sampleArticle(id: 'a', title: 'Saved A', date: '2026-07-02'),
      sampleArticle(id: 'b', title: 'Saved B', date: '2026-07-01'),
    ]);
    final apiClient = ApiClient(
      cache: cache,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await tester.pumpWidget(withLikeProviders(
      authState: AuthState(authClient: stubAuthClient()),
      likesClient: stubLikesClient(),
      child: MaterialApp(home: ArchiveScreen(apiClient: apiClient)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('SAVED A'), findsOneWidget);
    expect(find.text('SAVED B'), findsOneWidget);
    expect(find.text('OFFLINE · SHOWING SAVED ARTICLES'), findsOneWidget);
  });
}
