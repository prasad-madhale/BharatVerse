import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bharatverse_app/screens/home_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';

Map<String, dynamic> sampleArticleJson() => {
      'id': 'art_20260703_001',
      'title': 'The Mauryan Empire',
      'summary': 'A summary of the Mauryan Empire.',
      'content': '## Origins\n\nSome content.',
      'sections': [
        {'heading': 'Origins', 'content': 'Some content.', 'order': 1},
      ],
      'citations': [],
      'publication_date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'BharatVerse AI',
      'tags': ['mauryan-empire'],
      'image_url': null,
    };

void main() {
  testWidgets('shows the daily article once loaded', (tester) async {
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode(sampleArticleJson()), 200);
    });
    final apiClient = ApiClient(client: mockClient);

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(apiClient: apiClient)),
    );

    // Loading state first.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('The Mauryan Empire'), findsOneWidget);
    expect(find.text('A summary of the Mauryan Empire.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows an error state with retry when the request fails',
      (tester) async {
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      if (callCount == 1) {
        return http.Response('error', 500);
      }
      return http.Response(jsonEncode(sampleArticleJson()), 200);
    });
    final apiClient = ApiClient(client: mockClient);

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(apiClient: apiClient)),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('The Mauryan Empire'), findsOneWidget);
  });

  testWidgets('navigates to article detail on tap', (tester) async {
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode(sampleArticleJson()), 200);
    });
    final apiClient = ApiClient(client: mockClient);

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(apiClient: apiClient)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Card));
    await tester.pumpAndSettle();

    // Detail screen renders the markdown section heading.
    expect(find.text('Origins'), findsOneWidget);
  });
}
