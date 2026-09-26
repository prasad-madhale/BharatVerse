import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// Hide gotrue's own AuthState type -- it collides with our AuthState
// ChangeNotifier (see lib/state/auth_state.dart).
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'config.dart';
import 'screens/app_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/api_client.dart';
import 'services/article_cache.dart';
import 'services/likes_client.dart';
import 'services/pending_likes.dart';
import 'services/pending_saves.dart';
import 'services/reading_history.dart';
import 'services/saves_client.dart';
import 'state/auth_state.dart';
import 'state/like_state.dart';
import 'state/onboarding_state.dart';
import 'state/save_state.dart';
import 'state/settings_state.dart';
import 'state/theme_mode_state.dart';
import 'theme/app_theme.dart';
import 'widgets/recovery_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  final cache = await ArticleCache.open();
  final pendingLikes = await PendingLikes.open();
  final pendingSaves = await PendingSaves.open();
  final themeModeState = await ThemeModeState.open();
  final onboardingState = await OnboardingState.open();
  final readingHistory = await ReadingHistory.open();
  final settingsState = await SettingsState.open();
  runApp(BharatVerseApp(
    apiClient: ApiClient(cache: cache),
    pendingLikes: pendingLikes,
    pendingSaves: pendingSaves,
    themeModeState: themeModeState,
    onboardingState: onboardingState,
    readingHistory: readingHistory,
    settingsState: settingsState,
  ));
}

class BharatVerseApp extends StatelessWidget {
  final ApiClient apiClient;
  final PendingLikes pendingLikes;
  final PendingSaves pendingSaves;
  final ThemeModeState themeModeState;
  final OnboardingState onboardingState;
  final ReadingHistory readingHistory;
  final SettingsState settingsState;

  const BharatVerseApp({
    super.key,
    required this.apiClient,
    required this.pendingLikes,
    required this.pendingSaves,
    required this.themeModeState,
    required this.onboardingState,
    required this.readingHistory,
    required this.settingsState,
  });

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
            pendingLikes: pendingLikes,
          ),
        ),
        Provider(create: (_) => SavesClient()),
        // SaveState reads the two above, so it comes after them. It is not lazy,
        // so a returning user's saves are loaded before the first article opens.
        ChangeNotifierProvider(
          lazy: false,
          create: (context) => SaveState(
            savesClient: context.read<SavesClient>(),
            authState: context.read<AuthState>(),
            pendingSaves: pendingSaves,
          ),
        ),
        ChangeNotifierProvider.value(value: themeModeState),
        Provider.value(value: readingHistory),
        ChangeNotifierProvider.value(value: settingsState),
      ],
      child: Consumer<ThemeModeState>(
        builder: (context, themeModeState, _) => MaterialApp(
          title: 'BharatVerse',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeModeState.mode,
          home: RecoveryGate(
            child: onboardingState.seen
                ? AppShell(apiClient: apiClient)
                : OnboardingScreen(
                    apiClient: apiClient,
                    onboardingState: onboardingState,
                  ),
          ),
        ),
      ),
    );
  }
}
