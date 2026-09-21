import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bharatverse_app/widgets/suggestion_tile.dart';

import '../support/highlight_finder.dart';

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    String term = 'Mauryan Empire',
    String typed = 'mau',
    VoidCallback? onTap,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SuggestionTile(term: term, typed: typed, onTap: onTap ?? () {}),
        ),
      ));

  List<String> markedText(WidgetTester tester) =>
      marked(tester).where((text) => text.isNotEmpty).toList();

  group('SuggestionTile', () {
    testWidgets('marks the typed start of the term and shows all of it',
        (tester) async {
      await pumpTile(tester);

      expect(markedText(tester), ['Mau']);
      expect(find.text('Mauryan Empire', findRichText: true), findsOneWidget);
    });

    testWidgets('matches the typed text whatever its case', (tester) async {
      await pumpTile(tester, typed: 'MAURYAN e');

      expect(markedText(tester), ['Mauryan E']);
    });

    testWidgets('collapses the typed whitespace as the database does',
        (tester) async {
      await pumpTile(tester, typed: '  mauryan   e ');

      expect(markedText(tester), ['Mauryan E']);
    });

    testWidgets('marks all of a term that has been typed in full',
        (tester) async {
      await pumpTile(tester, typed: 'mauryan empire');

      expect(markedText(tester), ['Mauryan Empire']);
    });

    testWidgets('marks nothing when nothing is typed', (tester) async {
      await pumpTile(tester, typed: '   ');

      expect(markedText(tester), isEmpty);
    });

    testWidgets('never marks past the end of the term', (tester) async {
      await pumpTile(tester, term: 'Ashoka', typed: 'ashoka the great');

      expect(markedText(tester), ['Ashoka']);
    });

    testWidgets('puts the search icon before the term', (tester) async {
      await pumpTile(tester);

      expect(tester.getTopLeft(find.byType(Icon)).dx,
          lessThan(tester.getTopLeft(find.byType(Text)).dx));
    });

    testWidgets('reports a tap', (tester) async {
      var taps = 0;
      await pumpTile(tester, onTap: () => taps++);

      await tester.tap(find.byType(SuggestionTile));

      expect(taps, 1);
    });

    testWidgets('keeps a long term on one line', (tester) async {
      await pumpTile(tester, term: 'A very long title ' * 20, typed: 'a');

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.descendant(
          of: find.byType(SuggestionTile), matching: find.byType(Text)));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });
}
