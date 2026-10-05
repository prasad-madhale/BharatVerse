import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:bharatverse_app/main.dart' as app;
import 'package:bharatverse_app/screens/app_shell.dart';
import 'package:bharatverse_app/services/saves_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/account_avatar.dart';
import 'package:bharatverse_app/widgets/save_button.dart';
import 'package:bharatverse_app/widgets/settings_sheet.dart';

/// The real app against a database it may write to -- tools/local-stack, with
/// --dart-define=SUPABASE_URL and SUPABASE_ANON_KEY pointing at it, never the
/// hosted project: sign up, save a story, delete the account from Settings,
/// and find that the account can no longer sign in.
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

  testWidgets('a reader deletes their account from Settings', (tester) async {
    final email = 'e2e-${DateTime.now().millisecondsSinceEpoch}@example.com';
    const password = 'correct-horse-9';
    await (await SharedPreferences.getInstance()).clear();
    await app.main();
    await pumpUntil(tester, find.text('Get started'));

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await pumpUntil(tester, find.text('Create your account'));
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.tap(find.text('Create account'));
    await pumpUntil(tester, find.byType(AppShell));
    final authState = tester.element(find.byType(AppShell)).read<AuthState>();
    expect(authState.isAuthenticated, isTrue);

    await pumpUntil(tester, find.byType(SaveButton));
    await tester.tap(find.byType(SaveButton).first);
    await pumpUntil(tester, find.byIcon(Icons.bookmark));
    expect(
        await SavesClient()
            .getSavedArticleIds(accessToken: authState.authToken!),
        isNotEmpty);

    await tester.tap(find.byType(AccountAvatar));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Delete account'), 200,
        scrollable: find
            .descendant(
                of: find.byType(SettingsSheet),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await pumpUntil(tester, find.text('Your account has been deleted.'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsSheet), findsNothing);
    expect(authState.isAuthenticated, isFalse);
    await expectLater(
      Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password),
      throwsA(isA<AuthException>()),
    );
  });
}
