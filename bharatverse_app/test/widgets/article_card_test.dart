import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bharatverse_app/widgets/article_card.dart';

import '../support/article_fixtures.dart';
import '../support/highlight_finder.dart';

void main() {
  for (final size in ArticleCardSize.values) {
    testWidgets('the ${size.name} card shows the date and reading time',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ArticleCard(article: sampleArticle(), size: size, onTap: () {}),
        ),
      ));

      expect(find.text('2026-07-03 · 13 min read'), findsOneWidget);
    });
  }

  group('the compact card lists the tags a search term is in', () {
    Future<void> pump(WidgetTester tester, List<String> highlight,
        {ArticleCardSize size = ArticleCardSize.compact}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ArticleCard(
            article: sampleArticle(
                tags: const ['medieval-india', 'gupta-empire', 'chola']),
            size: size,
            onTap: () {},
            highlight: highlight,
          ),
        ),
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
