import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bharatverse_app/models/article.dart';
import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/like_button.dart';

import '../support/like_fixtures.dart';
import '../support/layout_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bharatverse_app/services/article_cache.dart';
import 'package:bharatverse_app/services/api_client.dart';

const _articleId = 'art_20260703_001';

Article sampleArticle() => Article.fromJson({
      'id': _articleId,
      'title': 'The Mauryan Empire',
      'summary': 'A summary.',
      'content': '## Origins\n\nSome content.',
      'sections': [
        {'heading': 'Origins', 'content': 'Some content.', 'order': 1},
      ],
      'citations': [],
      'publication_date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'BharatVerse AI',
      'tags': [],
      'image_url': null,
    });

void main() {
  late MockGoTrueClient authClient;
  late MockLikesClient likesClient;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      withLikeProviders(
        authState: AuthState(authClient: authClient),
        likesClient: likesClient,
        child: MaterialApp(
          home: ArticleDetailScreen(article: sampleArticle()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    authClient = stubAuthClient();
    likesClient = stubLikesClient();
  });

  group('ArticleDetailScreen', () {
    testWidgets('shows the article with a like button in the header',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('ORIGINS'), findsOneWidget);
      expect(find.byType(LikeButton), findsOneWidget);
    });

    testWidgets('a signed-out tap on the heart opens the sign-in screen',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsWidgets);
    });

    testWidgets('liking sends this article\'s id', (tester) async {
      authClient.signInAs(testUser());
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      verify(() => likesClient.like(
            accessToken: 'user-token',
            userId: 'user-123',
            articleId: _articleId,
          )).called(1);
    });
  });

  testWidgets('keeps the article in a readable column on a wide screen',
      (tester) async {
    useWideScreen(tester);
    await pumpScreen(tester);

    final article = find
        .descendant(of: find.byType(ListView), matching: find.byType(Container))
        .first;
    expect(tester.getSize(article).width, 720 - 2 * 20);
  });

  testWidgets('openArticle shows the article and saves the view',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cache = ArticleCache(await SharedPreferences.getInstance());
    final apiClient = ApiClient(cache: cache);
    await tester.pumpWidget(withLikeProviders(
      authState: AuthState(authClient: authClient),
      likesClient: likesClient,
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openArticle(context, apiClient, sampleArticle()),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(ArticleDetailScreen), findsOneWidget);
    expect(await cache.getCachedArticle(sampleArticle().id), isNotNull);
  });
}
