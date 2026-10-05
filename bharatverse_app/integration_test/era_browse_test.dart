import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/main.dart' as app;
import 'package:bharatverse_app/screens/app_shell.dart';
import 'package:bharatverse_app/screens/search_screen.dart';
import 'package:bharatverse_app/widgets/article_card.dart';

/// The real app against tools/local-stack (--dart-define=SUPABASE_URL and
/// SUPABASE_ANON_KEY), whose seeded articles carry eras from the era list:
/// a guest opens Search, taps an era card and gets that era's story.
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

  testWidgets('tapping an era card lists its stories', (tester) async {
    await (await SharedPreferences.getInstance()).clear();
    await app.main();
    await pumpUntil(tester, find.text('I already have an account'));
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now — just browse'));
    await pumpUntil(tester, find.byType(AppShell));

    await tester.tap(find.byTooltip('Search'));
    await pumpUntil(tester, find.byType(SearchScreen));
    await pumpUntil(tester, find.text('Browse by era'));
    final card = find.text('Indus Valley');
    await pumpUntil(tester, card);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);

    await pumpUntil(
        tester,
        find.descendant(
            of: find.byType(ArticleCard),
            matching: find.text('The Indus Valley Civilisation')));
  });
}
