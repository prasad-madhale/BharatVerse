import 'package:flutter/material.dart';
import 'package:porter_2_stemmer/porter_2_stemmer.dart';

import '../theme/app_colors.dart';

final _stemmer = Porter2Stemmer();
final _wordPattern = RegExp("[A-Za-z']+");
final _plainWordPattern = RegExp(r"^[A-Za-z']+$");

/// The (start, end) ranges in [text] worth marking for [terms]: any literal, case-insensitive
/// occurrence, plus -- for a term that is itself a plain word -- any word in [text] that stems to
/// the same root, so a search for "empires" marks "Empire" too (Postgres's search finds it the
/// same way). Overlapping and touching ranges are merged into one.
List<(int, int)> _matchRanges(String text, List<String> terms) {
  final found = <(int, int)>[];

  final literal = terms.where((term) => term.isNotEmpty).map(RegExp.escape);
  if (literal.isNotEmpty) {
    for (final match
        in RegExp(literal.join('|'), caseSensitive: false).allMatches(text)) {
      found.add((match.start, match.end));
    }
  }

  final wordTerms = terms.where((term) => _plainWordPattern.hasMatch(term));
  if (wordTerms.isNotEmpty) {
    final stems =
        wordTerms.map((term) => _stemmer.stem(term.toLowerCase())).toSet();
    for (final match in _wordPattern.allMatches(text)) {
      if (stems.contains(_stemmer.stem(match[0]!.toLowerCase()))) {
        found.add((match.start, match.end));
      }
    }
  }

  found.sort((a, b) => a.$1 - b.$1);
  final merged = <(int, int)>[];
  for (final range in found) {
    if (merged.isNotEmpty && range.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, range.$2 > last.$2 ? range.$2 : last.$2));
    } else {
      merged.add(range);
    }
  }
  return merged;
}

/// The terms of a websearch-style query worth highlighting: quoted phrases
/// whole, `-excluded` words and the `or` operator dropped.
List<String> searchTerms(String query) {
  final terms = <String>[];
  for (final match in RegExp(r'"([^"]+)"|(\S+)').allMatches(query)) {
    final phrase = match.group(1);
    final word = match.group(2);
    if (phrase != null) {
      terms.add(phrase.trim());
    } else if (word != null &&
        !word.startsWith('-') &&
        word.toLowerCase() != 'or') {
      terms.add(word.replaceAll(RegExp(r'^\W+|\W+$'), ''));
    }
  }
  return terms.where((term) => term.length >= 2).toSet().toList();
}

/// [text] with every case-insensitive occurrence of [terms] in bold saffron.
class HighlightedText extends StatelessWidget {
  final String text;
  final List<String> terms;
  final TextStyle style;
  final int? maxLines;

  const HighlightedText(
    this.text, {
    super.key,
    this.terms = const [],
    required this.style,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final ranges = _matchRanges(text, terms);
    if (ranges.isEmpty) {
      return Text(text,
          style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    final marked = style.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.accentPrimary,
    );
    final spans = <TextSpan>[];
    var last = 0;
    for (final (start, end) in ranges) {
      if (start > last) {
        spans.add(TextSpan(text: text.substring(last, start)));
      }
      spans.add(TextSpan(text: text.substring(start, end), style: marked));
      last = end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
