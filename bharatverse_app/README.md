# BharatVerse Mobile App

Cross-platform mobile application for iOS and Android built with Flutter.

## Overview

The BharatVerse mobile app provides:
- Daily historical articles about Indian history
- Article search with autocomplete
- User authentication (email/password + OAuth)
- Article likes and personalization
- Offline reading (last 7 days cached)
- Markdown rendering for rich content

## Prerequisites

- **Flutter SDK 3.x** or higher
- **Dart SDK** (included with Flutter)
- **Android Studio** (for Android development)
- **Xcode** (for iOS development, macOS only)
- **Backend API** running (see [backend/README.md](../backend/README.md))

## Setup

### 1. Install Flutter

Follow the official Flutter installation guide:
- [Flutter Installation](https://docs.flutter.dev/get-started/install)

Verify installation:
```bash
flutter doctor
```

### 2. Get Dependencies

```bash
cd bharatverse_app
flutter pub get
```

### 3. Configure API Endpoint

Edit `lib/config/api_config.dart`:

```dart
class ApiConfig {
  static const String baseUrl = 'http://localhost:8000';  // Development
  // static const String baseUrl = 'https://api.bharatverse.com';  // Production
}
```

### 4. Configure OAuth (Optional)

#### Google OAuth

1. Create OAuth credentials in [Google Cloud Console](https://console.cloud.google.com/)
2. Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<meta-data
    android:name="com.google.android.gms.auth.api.signin.client_id"
    android:value="YOUR_GOOGLE_CLIENT_ID" />
```
3. Add to `ios/Runner/Info.plist`:
```xml
<key>GIDClientID</key>
<string>YOUR_GOOGLE_CLIENT_ID</string>
```

#### Facebook OAuth

1. Create app in [Facebook Developers](https://developers.facebook.com/)
2. Follow [flutter_facebook_auth setup](https://pub.dev/packages/flutter_facebook_auth)

## Running the App

### Development Mode

```bash
# Run on connected device/emulator
flutter run

# Run with hot reload
flutter run --hot

# Run on specific device
flutter devices
flutter run -d <device-id>
```

### Debug vs Release

```bash
# Debug mode (default)
flutter run

# Profile mode (performance profiling)
flutter run --profile

# Release mode (optimized)
flutter run --release
```

## Building

### Android

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# App Bundle (for Play Store)
flutter build appbundle --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### iOS

```bash
# Debug build
flutter build ios --debug

# Release build
flutter build ios --release
```

Then open `ios/Runner.xcworkspace` in Xcode to archive and upload to App Store.

## Project Structure

```
bharatverse_app/
├── lib/
│   ├── main.dart              # App entry point
│   ├── config/                # Configuration
│   │   └── api_config.dart
│   ├── models/                # Data models
│   │   ├── article.dart
│   │   ├── user.dart
│   │   └── auth_response.dart
│   ├── services/              # API and business logic
│   │   ├── api_client.dart
│   │   ├── auth_service.dart
│   │   ├── article_cache.dart
│   │   └── secure_storage.dart
│   ├── state/                 # State management (Provider)
│   │   ├── article_state.dart
│   │   ├── auth_state.dart
│   │   └── like_state.dart
│   ├── screens/               # UI screens
│   │   ├── home_screen.dart
│   │   ├── article_detail_screen.dart
│   │   ├── search_screen.dart
│   │   ├── auth_screen.dart
│   │   └── profile_screen.dart
│   ├── widgets/               # Reusable widgets
│   │   ├── daily_article_card.dart
│   │   ├── article_list_tile.dart
│   │   ├── article_content_view.dart
│   │   └── like_button.dart
│   └── utils/                 # Utility functions
│       ├── date_formatter.dart
│       └── validators.dart
├── test/                      # Unit and widget tests
│   ├── widget_test.dart
│   ├── models/
│   ├── services/
│   └── widgets/
├── android/                   # Android-specific code
├── ios/                       # iOS-specific code
├── pubspec.yaml              # Dependencies
└── README.md                 # This file
```

## Dependencies

Key packages used:

- **provider** - State management
- **http** - HTTP client for API calls
- **shared_preferences** - Local key-value storage
- **sqflite** - Local SQLite database for caching
- **cached_network_image** - Image caching
- **flutter_secure_storage** - Secure token storage
- **google_sign_in** - Google OAuth
- **flutter_facebook_auth** - Facebook OAuth
- **flutter_markdown** - Markdown rendering

See `pubspec.yaml` for complete list.

## Testing

### Run All Tests

```bash
flutter test
```

### Run Specific Tests

```bash
# Widget tests
flutter test test/widgets/

# Unit tests
flutter test test/models/ test/services/

# Integration tests
flutter test integration_test/
```

### Test Coverage

```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Widget Testing

Example widget test:

```dart
testWidgets('DailyArticleCard displays article info', (WidgetTester tester) async {
  final article = Article(
    id: 'test_001',
    title: 'Test Article',
    summary: 'Test summary',
    // ... other fields
  );

  await tester.pumpWidget(
    MaterialApp(
      home: DailyArticleCard(article: article),
    ),
  );

  expect(find.text('Test Article'), findsOneWidget);
  expect(find.text('Test summary'), findsOneWidget);
});
```

## State Management

The app uses **Provider** for state management with three main state classes:

### ArticleState
Manages article data and loading states:
```dart
Provider.of<ArticleState>(context).fetchDailyArticle();
```

### AuthState
Manages authentication and user session:
```dart
Provider.of<AuthState>(context).login(email, password);
```

### LikeState
Manages article likes:
```dart
Provider.of<LikeState>(context).toggleLike(articleId);
```

## Offline Support

The app caches articles locally for offline reading:

- Articles cached after viewing
- Last 7 days retained
- Automatic sync when online
- Offline indicator in UI

Cache is managed by `ArticleCache` service using sqflite.

## Code Style

Follow Dart style guide:
- Use `lowerCamelCase` for variables and functions
- Use `UpperCamelCase` for classes
- Use `_lowerCamelCase` for private members
- Maximum line length: 80 characters
- Use trailing commas for better formatting

Format code:
```bash
flutter format lib/
```

Analyze code:
```bash
flutter analyze
```

## Development Workflow

1. **Create feature branch**: `git checkout -b feature/your-feature`
2. **Make changes** in `lib/`
3. **Write tests** in `test/`
4. **Run tests**: `flutter test`
5. **Format code**: `flutter format lib/`
6. **Analyze**: `flutter analyze`
7. **Commit**: `git commit -m "feat: your feature"`
8. **Push**: `git push origin feature/your-feature`

## Debugging

### Flutter DevTools

```bash
flutter pub global activate devtools
flutter pub global run devtools
```

Then run app with:
```bash
flutter run --observatory-port=9200
```

### Debug Logging

```dart
import 'package:flutter/foundation.dart';

debugPrint('Debug message');
```

### Network Debugging

Use Charles Proxy or Proxyman to inspect HTTP requests.

## Performance

### Optimization Tips

1. **Images**: Use `cached_network_image` for network images
2. **Lists**: Use `ListView.builder` for long lists
3. **State**: Minimize widget rebuilds with `const` constructors
4. **Async**: Use `FutureBuilder` and `StreamBuilder` appropriately
5. **Memory**: Dispose controllers and streams in `dispose()`

### Performance Profiling

```bash
flutter run --profile
```

Then use DevTools to analyze performance.

## Deployment

### Android (Google Play Store)

1. **Configure signing**: Edit `android/app/build.gradle`
2. **Build app bundle**: `flutter build appbundle --release`
3. **Upload to Play Console**: https://play.google.com/console
4. **Fill store listing** and submit for review

### iOS (App Store)

1. **Configure signing**: Open `ios/Runner.xcworkspace` in Xcode
2. **Build archive**: `flutter build ios --release`
3. **Archive in Xcode**: Product → Archive
4. **Upload to App Store Connect**: Window → Organizer
5. **Fill store listing** and submit for review

## Troubleshooting

### Build Errors

```bash
# Clean build
flutter clean
flutter pub get
flutter run
```

### Gradle Issues (Android)

```bash
cd android
./gradlew clean
cd ..
flutter run
```

### Pod Issues (iOS)

```bash
cd ios
pod deintegrate
pod install
cd ..
flutter run
```

### Hot Reload Not Working

```bash
# Restart app with hot reload enabled
flutter run --hot
```

## Platform-Specific Notes

### Android

- Minimum SDK: 21 (Android 5.0)
- Target SDK: 34 (Android 14)
- Permissions configured in `AndroidManifest.xml`

### iOS

- Minimum version: iOS 13.0
- Permissions configured in `Info.plist`
- Requires macOS for development

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Dart Documentation](https://dart.dev/guides)
- [Provider Package](https://pub.dev/packages/provider)
- [Flutter Cookbook](https://docs.flutter.dev/cookbook)
- [Design Document](../.kiro/specs/bharatverse-mvp/design.md)
- [AGENTS.md](../.kiro/AGENTS.md)

## Support

For issues or questions:
1. Check the [design document](../.kiro/specs/bharatverse-mvp/design.md)
2. Review [AGENTS.md](../.kiro/AGENTS.md) for development guidelines
3. Check existing issues in the repository
