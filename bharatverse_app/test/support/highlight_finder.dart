import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bharatverse_app/theme/app_colors.dart';

/// The texts currently drawn in the highlight color.
List<String> marked(WidgetTester tester) {
  final texts = <String>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text != null &&
          span.style?.color == AppColorTokens.light.accentPrimary) {
        texts.add(span.text!);
      }
      return true;
    });
  }
  return texts;
}
