import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bharatverse_app/widgets/article_card.dart';

import '../support/article_fixtures.dart';

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
}
