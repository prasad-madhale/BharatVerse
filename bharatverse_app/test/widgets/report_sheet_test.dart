import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/report_sheet.dart';

import '../support/like_fixtures.dart';

void main() {
  late List<http.Request> sent;
  late int status;

  setUp(() {
    sent = [];
    status = 201;
  });

  Future<void> open(WidgetTester tester, {AuthState? authState}) async {
    final apiClient = ApiClient(client: MockClient((request) async {
      sent.add(request);
      if (status == 0) throw http.ClientException('offline');
      return http.Response('', status);
    }));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: authState ?? AuthState(authClient: stubAuthClient()),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ReportSheet.show(context,
                    articleId: 'art_1', apiClient: apiClient),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  bool sendEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.ancestor(
              of: find.text('Send report'),
              matching: find.bySubtype<ButtonStyleButton>()))
          .onPressed !=
      null;

  testWidgets('lists every reason, and sends nothing until one is chosen',
      (tester) async {
    await open(tester);

    for (final label in reportReasons.values) {
      expect(find.text(label), findsOneWidget);
    }
    expect(sendEnabled(tester), isFalse);

    await tester.tap(find.text('Send report'));
    await tester.pump();
    expect(sent, isEmpty);
  });

  testWidgets(
      'sends the chosen reason and note anonymously, then thanks the reader',
      (tester) async {
    await open(tester);

    await tester.tap(find.text(reportReasons['image']!));
    await tester.enterText(find.byType(TextField), 'The fort is in Agra.');
    await tester.pump();
    expect(sendEnabled(tester), isTrue);
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(jsonDecode(sent.single.body), {
      'article_id': 'art_1',
      'reason': 'image',
      'note': 'The fort is in Agra.',
    });
    expect(find.byType(ReportSheet), findsNothing);
    expect(find.text("Thanks for the report. We'll look into it."),
        findsOneWidget);
  });

  testWidgets('signed in, the report carries the reader\'s id and token',
      (tester) async {
    await open(tester,
        authState: AuthState(
            authClient: stubAuthClient()..signInAs(testUser(id: 'user-9'))));

    await tester.tap(find.text(reportReasons['factual']!));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(jsonDecode(sent.single.body)['user_id'], 'user-9');
    expect(sent.single.headers['Authorization'], 'Bearer user-token');
  });

  testWidgets('offline, it says the report was not sent and keeps the note',
      (tester) async {
    status = 0;
    await open(tester);

    await tester.tap(find.text(reportReasons['other']!));
    await tester.enterText(find.byType(TextField), 'Typo in the title.');
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't send your report"), findsOneWidget);
    expect(find.byType(ReportSheet), findsOneWidget);
    expect(find.text('Typo in the title.'), findsOneWidget);
  });
}
