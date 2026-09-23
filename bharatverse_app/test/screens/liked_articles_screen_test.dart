import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/screens/liked_articles_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/app_button.dart';
import 'package:bharatverse_app/widgets/article_card.dart';

import '../support/article_fixtures.dart';
import '../support/like_fixtures.dart';

void main() {
  late MockLikesClient likes;
  late MockGoTrueClient authClient;

  final firstRow = sampleArticleRow(id: 'art_1', title: 'First');
  final secondRow = sampleArticleRow(id: 'art_2', title: 'Second');

  Future<void> pumpLiked(WidgetTester tester) async {
    await tester.pumpWidget(withLikeProviders(
      authState: AuthState(authClient: authClient),
      likesClient: likes,
      child: MaterialApp(
        home: LikedArticlesScreen(
          apiClient: ApiClient(client: articlesMockClient(() => [])),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  void stubLiked(Future<List<Map<String, dynamic>>> Function() answer) {
    when(() => likes.getLikedArticleRows(
          accessToken: any(named: 'accessToken'),
        )).thenAnswer((_) => answer());
  }

  List<String> listedIds(WidgetTester tester) => tester
      .widgetList<ArticleCard>(find.byType(ArticleCard))
      .map((card) => card.article.id)
      .toList();

  setUp(() {
    likes = stubLikesClient();
    authClient = stubAuthClient()..signInAs(testUser());
  });

  group('LikedArticlesScreen', () {
    testWidgets(
        'lists the liked articles in the order they come back, as the user',
        (tester) async {
      stubLiked(() async => [secondRow, firstRow]);

      await pumpLiked(tester);

      expect(listedIds(tester), ['art_2', 'art_1']);
      verify(() => likes.getLikedArticleRows(accessToken: 'user-token'))
          .called(1);
    });

    testWidgets('says so when nothing is liked yet', (tester) async {
      stubLiked(() async => []);

      await pumpLiked(tester);

      expect(find.text('NO LIKED ARTICLES'), findsOneWidget);
      expect(find.textContaining('Tap the heart'), findsOneWidget);
    });

    testWidgets('makes no request when nobody is signed in', (tester) async {
      authClient.signInAs(null);

      await pumpLiked(tester);

      expect(find.text('NO LIKED ARTICLES'), findsOneWidget);
      verifyNever(() => likes.getLikedArticleRows(
            accessToken: any(named: 'accessToken'),
          ));
    });

    testWidgets('shows a failure with a retry', (tester) async {
      var failNext = true;
      stubLiked(() async {
        if (failNext) {
          failNext = false;
          throw ApiException('Request failed (500)', statusCode: 500);
        }
        return [firstRow];
      });

      await pumpLiked(tester);
      expect(find.text('COULD NOT LOAD YOUR LIKES'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(listedIds(tester), ['art_1']);
    });

    testWidgets('refreshes after an article is unliked while reading it',
        (tester) async {
      when(() => likes.getLikedArticleIds(
            accessToken: any(named: 'accessToken'),
          )).thenAnswer((_) async => {'art_1', 'art_2'});
      var calls = 0;
      stubLiked(() async => ++calls == 1 ? [firstRow, secondRow] : [secondRow]);
      await pumpLiked(tester);

      await tester.tap(find.byType(ArticleCard).first);
      await tester.pumpAndSettle();
      expect(find.byType(ArticleDetailScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Unlike'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(listedIds(tester), ['art_2']);
      expect(calls, 2);
    });

    testWidgets('leaves the list alone when the article is still liked',
        (tester) async {
      when(() => likes.getLikedArticleIds(
            accessToken: any(named: 'accessToken'),
          )).thenAnswer((_) async => {'art_1', 'art_2'});
      stubLiked(() async => [firstRow, secondRow]);
      await pumpLiked(tester);

      await tester.tap(find.byType(ArticleCard).first);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(listedIds(tester), ['art_1', 'art_2']);
      verify(() => likes.getLikedArticleRows(
            accessToken: any(named: 'accessToken'),
          )).called(1);
    });
  });

  testWidgets('hides an unexpected error behind a generic message',
      (tester) async {
    stubLiked(() async => throw const FormatException('bad json'));

    await pumpLiked(tester);

    expect(
        find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.textContaining('FormatException'), findsNothing);
  });
}
