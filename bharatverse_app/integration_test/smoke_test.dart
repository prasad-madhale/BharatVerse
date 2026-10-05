import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/main.dart' as app;
import 'package:bharatverse_app/models/article.dart';
import 'package:bharatverse_app/screens/app_shell.dart';
import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/screens/library_screen.dart';
import 'package:bharatverse_app/screens/search_screen.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/account_avatar.dart';
import 'package:bharatverse_app/widgets/app_button.dart';
import 'package:bharatverse_app/widgets/article_card.dart';
import 'package:bharatverse_app/widgets/settings_sheet.dart';

/// The reader's main journey on a real device, against a database it may write
/// to -- tools/local-stack, with --dart-define=SUPABASE_URL and
/// SUPABASE_ANON_KEY pointing at it, never the hosted project: sign up, read
/// today's story, save it and find it in Library, search for it, sign out and
/// back in, then delete the account so the run leaves nothing behind.
/// `scripts/e2e.sh` runs it with the other end-to-end tests.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps until [finder] matches; network calls finish in real time here.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for $finder');
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byType(AccountAvatar));
    await tester.pumpAndSettle();
  }

  Future<void> scrollSettingsTo(WidgetTester tester, String label) =>
      tester.scrollUntilVisible(find.text(label), 200,
          scrollable: find
              .descendant(
                  of: find.byType(SettingsSheet),
                  matching: find.byType(Scrollable))
              .first);

  testWidgets('sign up, read, save, find in Library, search, sign out and in',
      (tester) async {
    final email = 'smoke-${DateTime.now().millisecondsSinceEpoch}@example.com';
    const password = 'correct-horse-9';
    await (await SharedPreferences.getInstance()).clear();
    await app.main();
    await pumpUntil(tester, find.text('Get started'));

    // Sign up from onboarding.
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await pumpUntil(tester, find.text('Create your account'));
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.tap(find.text('Create account'));
    await pumpUntil(tester, find.byType(AppShell));
    final auth = tester.element(find.byType(AppShell)).read<AuthState>();
    expect(auth.isAuthenticated, isTrue);

    // Read today's story and save it.
    await pumpUntil(tester, find.byType(ArticleCard));
    await tester.tap(find.byType(ArticleCard).first);
    await pumpUntil(tester, find.byType(ArticleDetailScreen));
    await tester.pumpAndSettle();
    final story = tester
        .widget<ArticleDetailScreen>(find.byType(ArticleDetailScreen))
        .article;
    await tester.tap(find.text('Save'));
    await pumpUntil(tester, find.text('Saved'));
    await tester.pageBack();
    await tester.pumpAndSettle();

    // It is in Library, under Saved.
    await tester.tap(find.text('Library'));
    await pumpUntil(tester, find.text('Saved · 1'));
    expect(
        find.descendant(
            of: find.byType(LibraryScreen), matching: find.text(story.title)),
        findsWidgets);

    // Search finds it by a word from its title.
    await tester.tap(find.byTooltip('Search'));
    await pumpUntil(tester, find.byType(SearchScreen));
    await tester.enterText(find.byType(TextField).first, _searchWord(story));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpUntil(
        tester,
        find.descendant(
            of: find.byType(ArticleCard), matching: find.text(story.title)));
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Sign out, then back in.
    await openSettings(tester);
    await scrollSettingsTo(tester, 'Sign out');
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.isAuthenticated, isFalse);
    await tester.tap(find.byType(AccountAvatar));
    await pumpUntil(tester, find.text('Welcome back'));
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.tap(find.widgetWithText(AppButton, 'Sign in'));
    await pumpUntil(tester, find.byType(AppShell));
    await tester.pumpAndSettle();
    expect(auth.isAuthenticated, isTrue);

    // Leave nothing behind.
    await openSettings(tester);
    await scrollSettingsTo(tester, 'Delete account');
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await pumpUntil(tester, find.text('Your account has been deleted.'));
    expect(auth.isAuthenticated, isFalse);
  });
}

/// The longest word of the story's title, which search must find it by.
String _searchWord(Article story) => (story.title
        .split(RegExp(r'[^A-Za-z]+'))
        .where((w) => w.length > 3)
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length)))
    .first;
