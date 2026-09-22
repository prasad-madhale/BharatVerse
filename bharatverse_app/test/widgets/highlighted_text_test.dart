import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bharatverse_app/widgets/highlighted_text.dart';

import '../support/highlight_finder.dart';

Future<void> pump(WidgetTester tester, String text, List<String> terms) =>
    tester.pumpWidget(MaterialApp(
      home: HighlightedText(text,
          terms: terms, style: const TextStyle(fontSize: 14)),
    ));

void main() {
  group('HighlightedText', () {
    testWidgets('marks every occurrence, whatever the case', (tester) async {
      await pump(
          tester, 'The Mauryan empire and the MAURYAN army', ['mauryan']);

      expect(marked(tester), ['Mauryan', 'MAURYAN']);
    });

    testWidgets('marks any of several terms', (tester) async {
      await pump(tester, 'Ashoka and the Cholas', ['chola', 'ashoka']);

      expect(marked(tester), ['Ashoka', 'Chola']);
    });

    testWidgets('leaves the text plain when there is nothing to mark',
        (tester) async {
      await pump(tester, 'Ashoka and the Cholas', []);
      expect(find.text('Ashoka and the Cholas'), findsOneWidget);
      expect(marked(tester), isEmpty);

      await pump(tester, 'Ashoka and the Cholas', ['harappa']);
      expect(find.text('Ashoka and the Cholas'), findsOneWidget);
      expect(marked(tester), isEmpty);
    });

    testWidgets('treats regular-expression characters literally',
        (tester) async {
      await pump(tester, 'Learning c++ (fast)', ['c++', '(fast)']);

      expect(marked(tester), ['c++', '(fast)']);
    });
  });

  group('searchTerms', () {
    test('splits words', () {
      expect(searchTerms('Ashoka dhamma'), ['Ashoka', 'dhamma']);
    });

    test('keeps quoted phrases whole', () {
      expect(searchTerms('"Bay of Bengal" chola'), ['Bay of Bengal', 'chola']);
    });

    test('drops exclusions and the or operator', () {
      expect(searchTerms('ancient -harappa or maurya'), ['ancient', 'maurya']);
    });

    test('trims punctuation and ignores one-letter terms', () {
      expect(searchTerms('Ashoka, a "x" dhamma!'), ['Ashoka', 'dhamma']);
    });

    test('drops repeats', () {
      expect(searchTerms('chola chola'), ['chola']);
    });
  });
}
