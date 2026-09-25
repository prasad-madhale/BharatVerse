import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bharatverse_app/models/article.dart';
import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/theme/app_colors.dart';
import 'package:bharatverse_app/widgets/article_image.dart';
import 'package:bharatverse_app/widgets/like_button.dart';

import '../support/article_fixtures.dart' show sampleImage;
import '../support/like_fixtures.dart';
import '../support/layout_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bharatverse_app/services/article_cache.dart';
import 'package:bharatverse_app/services/api_client.dart';

const _articleId = 'art_20260703_001';

Article sampleArticle({
  List<Map<String, dynamic>> sections = const [
    {'heading': 'Origins', 'content': 'Some content.', 'order': 1},
  ],
  List<Map<String, dynamic>> images = const [],
}) =>
    Article.fromJson({
      'id': _articleId,
      'title': 'The Mauryan Empire',
      'summary': 'A summary.',
      'content': '## Origins\n\nSome content.',
      'sections': sections,
      'citations': [],
      'images': images,
      'publication_date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'BharatVerse AI',
      'tags': [],
      'image_url': images.isNotEmpty ? images.first['url'] as String : null,
    });

void main() {
  late MockGoTrueClient authClient;
  late MockLikesClient likesClient;
  late MockSavesClient savesClient;

  Future<void> pumpScreen(WidgetTester tester, {Article? article}) async {
    await tester.pumpWidget(
      withLikeProviders(
        authState: AuthState(authClient: authClient),
        likesClient: likesClient,
        savesClient: savesClient,
        child: MaterialApp(
          home: ArticleDetailScreen(article: article ?? sampleArticle()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    authClient = stubAuthClient();
    likesClient = stubLikesClient();
    savesClient = stubSavesClient();
  });

  group('ArticleDetailScreen', () {
    testWidgets('shows the article with a like button in the header',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('ORIGINS'), findsOneWidget);
      expect(find.byType(LikeButton), findsOneWidget);
    });

    testWidgets('shows a parchment placeholder when the article has no images',
        (tester) async {
      await pumpScreen(tester);

      expect(find.byType(ArticleImageView), findsNothing);
      expect(
        find.byWidgetPredicate(
            (w) => w is Container && w.color == AppColorTokens.light.paper200),
        findsOneWidget,
      );
    });

    testWidgets('shows the featured image as the hero', (tester) async {
      await pumpScreen(tester, article: sampleArticle(images: [sampleImage()]));

      expect(find.byType(ArticleImageView), findsOneWidget);
      final picture =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(picture.imageUrl, 'https://storage.example/0.jpg');
    });

    testWidgets('distributes inline images (beyond the hero) between sections',
        (tester) async {
      await pumpScreen(
        tester,
        article: sampleArticle(
          sections: [
            {'heading': 'Origins', 'content': 'Some content.', 'order': 1},
            {'heading': 'Rise', 'content': 'More content.', 'order': 2},
          ],
          images: [
            sampleImage(url: 'https://storage.example/hero.jpg'),
            sampleImage(
                url: 'https://storage.example/inline.jpg', caption: null),
          ],
        ),
      );

      expect(find.byType(ArticleImageView), findsNWidgets(2));
      final pictures = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .map((p) => p.imageUrl)
          .toList();
      expect(pictures, [
        'https://storage.example/hero.jpg',
        'https://storage.example/inline.jpg'
      ]);
    });

    testWidgets('a signed-out tap on the heart opens the sign-in screen',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
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
      savesClient: savesClient,
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
