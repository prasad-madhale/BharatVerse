import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bharatverse_app/theme/app_colors.dart';
import 'package:bharatverse_app/theme/app_theme.dart';
import 'package:bharatverse_app/widgets/app_icon_button.dart';

void main() {
  testWidgets(
      'tints hover, press and ripple from the parchment and saffron palette',
      (tester) async {
    final theme = AppTheme.theme;

    expect(theme.hoverColor, AppColors.surfaceSunken);
    expect(theme.highlightColor, AppColors.surfaceSunken);
    expect(theme.splashColor, AppColors.accentPrimaryTint);
  });

  testWidgets('shows snackbars as paper on ink', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Saved'))),
            child: const Text('show'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    final material = tester.widget<Material>(find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first);
    expect(material.color, AppColors.ink950);
    expect(AppTheme.theme.snackBarTheme.contentTextStyle?.color,
        AppColors.textOnAccent);
  });

  testWidgets('shows tooltips as paper on ink', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(
        body: Center(
          child: AppIconButton(
              icon: Icons.search, label: 'Search', onPressed: () {}),
        ),
      ),
    ));

    await tester.longPress(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    final tooltipBox = find.byWidgetPredicate((widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).color == AppColors.ink950);
    expect(tooltipBox, findsOneWidget);
  });
}
