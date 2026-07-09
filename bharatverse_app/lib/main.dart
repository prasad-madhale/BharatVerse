import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// Hide gotrue's own AuthState type -- it collides with our AuthState
// ChangeNotifier (see lib/state/auth_state.dart).
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'config.dart';
import 'screens/home_screen.dart';
import 'services/api_client.dart';
import 'state/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const BharatVerseApp());
}

class BharatVerseApp extends StatelessWidget {
  const BharatVerseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthState(),
      child: MaterialApp(
        title: 'BharatVerse',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightGreen),
        ),
        home: HomeScreen(apiClient: ApiClient()),
      ),
    );
  }
}
