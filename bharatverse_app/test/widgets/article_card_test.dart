import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bharatverse_app/models/article.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/theme/app_colors.dart';
import 'package:bharatverse_app/widgets/article_card.dart';

import '../support/article_fixtures.dart';
import '../support/highlight_finder.dart';
import '../support/like_fixtures.dart';

Widget _pumpCard({
  required Article article,
  required ArticleCardSize size,
  List<String> highlight = const [],
}) =>
    withLikeProviders(
      authState: AuthState(authClient: stubAuthClient()),
      likesClient: stubLikesClient(),
      savesClient: stubSavesClient(),
      child: MaterialApp(
        home: Scaffold(
          // A bare Scaffold body isn't scrollable, but the real app always
          // hosts an ArticleCard inside one (ListView), and the featured
          // variant's stacked image+text is taller than a test viewport.
          body: SingleChildScrollView(
            child: ArticleCard(
              article: article,
              size: size,
              onTap: () {},
              onRequireAuth: () {},
              highlight: highlight,
            ),
          ),
        ),
      ),
    );

void main() {
  for (final size in ArticleCardSize.values) {
    testWidgets('the ${size.name} card shows the era and reading time',
        (tester) async {
      await tester.pumpWidget(_pumpCard(article: sampleArticle(), size: size));

      expect(find.textContaining('Ancient India'), findsOneWidget);
      expect(find.textContaining('13 min'), findsOneWidget);
    });

    testWidgets(
        'the ${size.name} card omits the era when the article predates it',
        (tester) async {
      await tester
          .pumpWidget(_pumpCard(article: sampleArticle(era: ''), size: size));

      expect(find.textContaining('Ancient India'), findsNothing);
    });

    testWidgets(
        'the ${size.name} card shows a parchment placeholder with no image',
        (tester) async {
      await tester.pumpWidget(_pumpCard(article: sampleArticle(), size: size));

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(
        find.byWidgetPredicate(
            (w) => w is Container && w.color == AppColorTokens.light.paper100),
        findsOneWidget,
      );
    });

    testWidgets(
        'the ${size.name} card shows the featured image when there is one',
        (tester) async {
      await tester.pumpWidget(_pumpCard(
        article: sampleArticle(imageUrl: 'https://storage.example/0.jpg'),
        size: size,
      ));

      final picture =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(picture.imageUrl, 'https://storage.example/0.jpg');
    });
  }

  group('the compact card lists the tags a search term is in', () {
    Future<void> pump(WidgetTester tester, List<String> highlight,
        {ArticleCardSize size = ArticleCardSize.compact}) async {
      await tester.pumpWidget(_pumpCard(
        article: sampleArticle(
            tags: const ['medieval-india', 'gupta-empire', 'chola']),
        size: size,
        highlight: highlight,
      ));
    }

    testWidgets('and marks the term in them', (tester) async {
      await pump(tester, ['medieval']);

      expect(find.text('Tagged: medieval-india'), findsOneWidget);
      expect(marked(tester), ['medieval']);
    });

    testWidgets('naming only the tags that match', (tester) async {
      await pump(tester, ['india', 'chola']);

      expect(find.text('Tagged: medieval-india, chola'), findsOneWidget);
    });

    testWidgets('whatever the case', (tester) async {
      await pump(tester, ['GUPTA']);

      expect(find.text('Tagged: gupta-empire'), findsOneWidget);
    });

    testWidgets('but not when no tag has one', (tester) async {
      await pump(tester, ['maurya']);

      expect(find.textContaining('Tagged'), findsNothing);
    });

    testWidgets('or when there is nothing to highlight', (tester) async {
      await pump(tester, []);

      expect(find.textContaining('Tagged'), findsNothing);
    });

    testWidgets('and an empty term matches nothing', (tester) async {
      await pump(tester, ['']);

      expect(find.textContaining('Tagged'), findsNothing);
    });

    testWidgets('while the featured card leaves tags out', (tester) async {
      await pump(tester, ['medieval'], size: ArticleCardSize.featured);

      expect(find.textContaining('Tagged'), findsNothing);
    });
  });
}
