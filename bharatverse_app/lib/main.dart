import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// Hide gotrue's own AuthState type -- it collides with our AuthState
// ChangeNotifier (see lib/state/auth_state.dart).
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'config.dart';
import 'screens/home_screen.dart';
import 'services/api_client.dart';
import 'services/article_cache.dart';
import 'services/likes_client.dart';
import 'state/auth_state.dart';
import 'state/like_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  final cache = await ArticleCache.open();
  runApp(BharatVerseApp(apiClient: ApiClient(cache: cache)));
}

class BharatVerseApp extends StatelessWidget {
  final ApiClient apiClient;

  const BharatVerseApp({super.key, required this.apiClient});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthState()),
        Provider(create: (_) => LikesClient()),
        // LikeState reads the two above, so it comes after them. It is not lazy,
        // so a returning user's likes are loaded before the first article opens.
        ChangeNotifierProvider(
          lazy: false,
          create: (context) => LikeState(
            likesClient: context.read<LikesClient>(),
            authState: context.read<AuthState>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'BharatVerse',
        theme: AppTheme.theme,
        home: HomeScreen(apiClient: apiClient),
      ),
    );
  }
}
