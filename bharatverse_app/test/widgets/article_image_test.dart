import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:bharatverse_app/models/article.dart';
import 'package:bharatverse_app/widgets/article_image.dart';

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

void main() {
  late _MockUrlLauncher launcher;

  final image = ArticleImage(
    url: 'https://storage.example/0.jpg',
    altText: 'The Great Stupa',
    caption: 'A restored Mauryan-era stupa',
    credit: 'Jane Doe via Wikimedia Commons',
    sourceUrl: 'https://commons.wikimedia.org/wiki/File:Stupa.jpg',
    license: 'CC BY-SA 4.0',
  );

  setUpAll(() {
    registerFallbackValue(
        const LaunchOptions(mode: PreferredLaunchMode.platformDefault));
  });

  setUp(() {
    launcher = _MockUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  Future<void> pumpImage(WidgetTester tester, ArticleImage image) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ArticleImageView(image: image)),
    ));
    // CachedNetworkImage has no real network in tests; settle past its error state
    // instead of pumpAndSettle(), which would wait on its retry timers forever.
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('ArticleImageView', () {
    testWidgets('shows the image at the given url, caption and credit line',
        (tester) async {
      await pumpImage(tester, image);

      final picture = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(picture.imageUrl, 'https://storage.example/0.jpg');
      expect(find.text('A restored Mauryan-era stupa'), findsOneWidget);
      expect(find.text('Jane Doe via Wikimedia Commons · CC BY-SA 4.0'),
          findsOneWidget);
    });

    testWidgets('omits the caption line when there is none', (tester) async {
      await pumpImage(
        tester,
        ArticleImage(
          url: image.url,
          altText: image.altText,
          credit: image.credit,
          sourceUrl: image.sourceUrl,
          license: image.license,
        ),
      );

      expect(find.text('A restored Mauryan-era stupa'), findsNothing);
      expect(find.text('Jane Doe via Wikimedia Commons · CC BY-SA 4.0'),
          findsOneWidget);
    });

    testWidgets('tapping the credit line opens the source url', (tester) async {
      when(() => launcher.launchUrl(any(), any()))
          .thenAnswer((_) async => true);
      await pumpImage(tester, image);

      await tester
          .tap(find.text('Jane Doe via Wikimedia Commons · CC BY-SA 4.0'));
      await tester.pump();

      verify(() => launcher.launchUrl(
            'https://commons.wikimedia.org/wiki/File:Stupa.jpg',
            any(),
          )).called(1);
    });

    testWidgets('shows a message when the source cannot be opened',
        (tester) async {
      when(() => launcher.launchUrl(any(), any()))
          .thenAnswer((_) async => false);
      await pumpImage(tester, image);

      await tester
          .tap(find.text('Jane Doe via Wikimedia Commons · CC BY-SA 4.0'));
      await tester.pump();

      expect(find.text("Couldn't open that source"), findsOneWidget);
    });

    testWidgets('the credit line is announced as a tappable link',
        (tester) async {
      await pumpImage(tester, image);

      final flags = tester
          .getSemantics(
              find.text('Jane Doe via Wikimedia Commons · CC BY-SA 4.0'))
          .flagsCollection;
      expect(flags.isButton, isTrue);
      expect(flags.isLink, isTrue);
    });
  });
}
