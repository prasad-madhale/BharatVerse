import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bharatverse_app/widgets/app_back_bar.dart';
import 'package:bharatverse_app/widgets/content_column.dart';

import '../support/layout_fixtures.dart';

void main() {
  group('ContentColumn', () {
    testWidgets('caps the width of its child and centers it on a wide screen',
        (tester) async {
      useWideScreen(tester);

      await tester.pumpWidget(const MaterialApp(
        home: ContentColumn(
            child:
                SizedBox(key: Key('box'), width: double.infinity, height: 10)),
      ));

      expect(tester.getSize(find.byKey(const Key('box'))).width, 720);
      expect(tester.getCenter(find.byKey(const Key('box'))).dx, 800);
    });

    testWidgets('leaves a narrow screen alone', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(
        home: ContentColumn(
            child:
                SizedBox(key: Key('box'), width: double.infinity, height: 10)),
      ));

      expect(tester.getSize(find.byKey(const Key('box'))).width, 400);
    });

    testWidgets('honors a narrower maxWidth', (tester) async {
      useWideScreen(tester);

      await tester.pumpWidget(const MaterialApp(
        home: ContentColumn(
            maxWidth: 420,
            child:
                SizedBox(key: Key('box'), width: double.infinity, height: 10)),
      ));

      expect(tester.getSize(find.byKey(const Key('box'))).width, 420);
    });
  });

  group('columnPadding', () {
    Future<EdgeInsets> padding(WidgetTester tester, Size size,
        {double horizontal = 16, double vertical = 0}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late EdgeInsets result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          result = columnPadding(context,
              horizontal: horizontal, vertical: vertical);
          return const SizedBox();
        }),
      ));
      return result;
    }

    testWidgets('is just the base padding on a screen no wider than the column',
        (tester) async {
      expect(await padding(tester, const Size(400, 800)),
          const EdgeInsets.symmetric(horizontal: 16));
      expect(await padding(tester, const Size(720, 800)),
          const EdgeInsets.symmetric(horizontal: 16));
    });

    testWidgets('adds a gutter that centers the column on a wider screen',
        (tester) async {
      expect(await padding(tester, const Size(1600, 1000)),
          const EdgeInsets.symmetric(horizontal: 440 + 16));
    });

    testWidgets('takes the base horizontal and vertical padding',
        (tester) async {
      expect(
          await padding(tester, const Size(1600, 1000),
              horizontal: 20, vertical: 8),
          const EdgeInsets.symmetric(horizontal: 440 + 20, vertical: 8));
    });
  });

  group('AppBackBar', () {
    testWidgets('shows a title and a trailing action, and goes back',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const Scaffold(
                  appBar: AppBackBar(title: 'ARTICLE', trailing: Text('extra')),
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('ARTICLE'), findsOneWidget);
      expect(find.text('extra'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('ARTICLE'), findsNothing);
    });

    testWidgets('keeps the back button in the reading column on a wide screen',
        (tester) async {
      useWideScreen(tester);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(appBar: AppBackBar())),
      );

      // The button's 48px tap target is centered around its 40px box.
      expect(tester.getTopLeft(find.byTooltip('Back')).dx, closeTo(440, 8));
    });
  });
}
