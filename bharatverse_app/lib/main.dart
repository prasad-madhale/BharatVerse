import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/api_client.dart';

void main() {
  runApp(const BharatVerseApp());
}

class BharatVerseApp extends StatelessWidget {
  const BharatVerseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BharatVerse',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightGreen),
      ),
      home: HomeScreen(apiClient: ApiClient()),
    );
  }
}
