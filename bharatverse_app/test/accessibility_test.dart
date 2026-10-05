import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/models/article.dart';
import 'package:bharatverse_app/screens/app_shell.dart';
import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/screens/auth_screen.dart';
import 'package:bharatverse_app/screens/search_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/services/reading_history.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/state/settings_state.dart';
import 'package:bharatverse_app/state/theme_mode_state.dart';
import 'package:bharatverse_app/theme/app_theme.dart';
import 'package:bharatverse_app/widgets/settings_sheet.dart';

import 'support/article_fixtures.dart';
import 'support/like_fixtures.dart';

/// The main screens, in both themes and at double the system text size, meet
/// Flutter's accessibility guidelines: 48dp tap targets, a label on everything
/// tappable, readable text contrast, and no layout overflow.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Widget> app(Widget home,
      {required bool dark, bool signedIn = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ReadingHistory(prefs)),
        ChangeNotifierProvider.value(value: SettingsState(prefs)),
        ChangeNotifierProvider.value(value: ThemeModeState(prefs)),
      ],
      child: withLikeProviders(
        authState: AuthState(
            authClient: stubAuthClient()
              ..signInAs(signedIn ? testUser() : null)),
        likesClient: stubLikesClient(),
        savesClient: stubSavesClient(),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!),
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: home,
        ),
      ),
    );
  }

  ApiClient apiClient() =>
      ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));

  Article article() => Article.fromJson({
        ...sampleArticleRow(),
        ...sampleArticleContent(),
        'publication_date': '2026-07-03',
      });

  Widget settingsLauncher() => Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => SettingsSheet.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

  Future<void> meetsGuidelines(WidgetTester tester) async {
    expect(tester.takeException(), isNull, reason: 'a layout overflowed');
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('$theme: Today', (tester) async {
      final handle = tester.ensureSemantics();
      await tester
          .pumpWidget(await app(AppShell(apiClient: apiClient()), dark: dark));
      await tester.pumpAndSettle();
      await meetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('$theme: an article', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          await app(ArticleDetailScreen(article: article()), dark: dark));
      await tester.pumpAndSettle();
      await meetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('$theme: Search', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          await app(SearchScreen(apiClient: apiClient()), dark: dark));
      await tester.pumpAndSettle();
      await meetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('$theme: sign-up', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          await app(const AuthScreen(initialSignUp: true), dark: dark));
      await tester.pumpAndSettle();
      await meetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('$theme: Settings', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
          await app(settingsLauncher(), dark: dark, signedIn: true));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await meetsGuidelines(tester);
      handle.dispose();
    });
  }

  testWidgets(
      'a screen reader hears each switch with its setting and each text size by name',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(await app(settingsLauncher(), dark: false, signedIn: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final dailyStory = tester.getSemantics(find.byType(Switch).first);
    expect(dailyStory.label, contains('Daily story'));
    for (final size in ['Small text', 'Medium text', 'Large text']) {
      expect(find.bySemanticsLabel(size), findsOneWidget);
    }
    handle.dispose();
  });

  testWidgets(
      'an article keeps the status bar on page colour as the story scrolls under it',
      (tester) async {
    tester.view.padding = const FakeViewPadding(top: 132);
    tester.view.viewPadding = const FakeViewPadding(top: 132);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        await app(ArticleDetailScreen(article: article()), dark: false));
    await tester.pumpAndSettle();

    final strip = find.byWidgetPredicate((w) =>
        w is ColoredBox && w.color == AppTheme.light.scaffoldBackgroundColor);
    expect(strip, findsWidgets);
    expect(tester.getRect(strip.first).height, 44);
  });
}
