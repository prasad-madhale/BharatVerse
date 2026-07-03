// Integration test that renders the real app against a mocked API response
// (real generated article content from scrapper_main.py) on an actual
// device/browser -- real fonts, real rendering, unlike headless `flutter
// test` widget tests. Run with:
//   flutter test integration_test/app_screenshot_test.dart -d chrome
//   flutter test integration_test/app_screenshot_test.dart -d macos

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bharatverse_app/screens/home_screen.dart';
import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/models/article.dart';
import 'package:bharatverse_app/services/api_client.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final articleJson = jsonDecode(
    File('/tmp/generated_article.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  testWidgets('HomeScreen renders the real generated article', (tester) async {
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode(articleJson), 200);
    });
    final apiClient = ApiClient(client: mockClient);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightGreen)),
        home: HomeScreen(apiClient: apiClient),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(articleJson['title'] as String), findsOneWidget);

    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('home_screen');
  });

  testWidgets('ArticleDetailScreen renders the real generated article', (tester) async {
    final article = Article.fromJson(articleJson);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightGreen)),
        home: ArticleDetailScreen(article: article),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(article.sections.first.heading), findsOneWidget);

    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('article_detail_screen');
  });
}
