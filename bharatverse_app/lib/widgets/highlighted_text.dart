import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

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
    final pattern = terms.where((term) => term.isNotEmpty).map(RegExp.escape);
    if (pattern.isEmpty) {
      return Text(text,
          style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    final marked = style.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.accentPrimary,
    );
    final spans = <TextSpan>[];
    var last = 0;
    for (final match
        in RegExp(pattern.join('|'), caseSensitive: false).allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      spans.add(TextSpan(text: match[0], style: marked));
      last = match.end;
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
