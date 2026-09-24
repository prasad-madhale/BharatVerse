import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:bharatverse_app/models/article.dart';
import 'package:bharatverse_app/widgets/citation_item.dart';

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

void main() {
  late _MockUrlLauncher launcher;

  final citation = ArticleCitation(
    text: 'A History of India',
    sourceUrl: 'https://example.com/history',
    sourceName: 'Example Source',
    accessedDate: DateTime(2026, 1, 1),
  );

  setUpAll(() {
    registerFallbackValue(const LaunchOptions(mode: PreferredLaunchMode.platformDefault));
  });

  setUp(() {
    launcher = _MockUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  Future<void> pumpItem(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CitationItem(citation: citation)),
    ));
  }

  group('CitationItem', () {
    testWidgets('shows the source name and citation text', (tester) async {
      await pumpItem(tester);

      expect(find.text('EXAMPLE SOURCE'), findsOneWidget);
      expect(find.text('A History of India'), findsOneWidget);
    });

    testWidgets('tapping it opens the source URL', (tester) async {
      when(() => launcher.launchUrl(any(), any()))
          .thenAnswer((_) async => true);
      await pumpItem(tester);

      await tester.tap(find.byType(CitationItem));
      await tester.pumpAndSettle();

      verify(() => launcher.launchUrl(
            'https://example.com/history',
            any(),
          )).called(1);
    });

    testWidgets('is announced as a tappable link for accessibility',
        (tester) async {
      await pumpItem(tester);

      final flags =
          tester.getSemantics(find.byType(CitationItem)).flagsCollection;
      expect(flags.isButton, isTrue);
      expect(flags.isLink, isTrue);
    });

    testWidgets('shows a message when the source cannot be opened',
        (tester) async {
      when(() => launcher.launchUrl(any(), any()))
          .thenAnswer((_) async => false);
      await pumpItem(tester);

      await tester.tap(find.byType(CitationItem));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't open that source"), findsOneWidget);
    });
  });
}
