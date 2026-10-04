import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/main.dart' as app;
import 'package:bharatverse_app/screens/app_shell.dart';
import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/widgets/article_card.dart';
import 'package:bharatverse_app/widgets/report_sheet.dart';

/// The real app against a database it may write to -- tools/local-stack, with
/// --dart-define=SUPABASE_URL and SUPABASE_ANON_KEY pointing at it, never the
/// hosted project: a guest opens today's story and reports a problem with it.
/// The note to look for in `article_reports` is passed as REPORT_NOTE.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const note = String.fromEnvironment('REPORT_NOTE', defaultValue: 'e2e');

  /// Pumps until [finder] matches; network calls finish in real time here.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for $finder');
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('a guest reports a problem with a story', (tester) async {
    await (await SharedPreferences.getInstance()).clear();
    await app.main();
    await pumpUntil(tester, find.text('I already have an account'));

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now — just browse'));
    await pumpUntil(tester, find.byType(AppShell));
    await pumpUntil(tester, find.byType(ArticleCard));

    await tester.tap(find.byType(ArticleCard).first);
    await pumpUntil(tester, find.byType(ArticleDetailScreen));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Report a problem'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report a problem'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(reportReasons['factual']!));
    await tester.enterText(find.byType(TextField), note);
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await pumpUntil(
        tester, find.text("Thanks for the report. We'll look into it."));
    await tester.pumpAndSettle();

    expect(find.byType(ReportSheet), findsNothing);
  });
}
