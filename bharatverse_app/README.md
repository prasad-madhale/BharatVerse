# Flutter app

The reader: today's article, an archive of earlier ones, search, likes and offline reading. It runs on Android, iOS and
the web.

## How it works

The app talks to Supabase directly, not through the [backend API](../backend/README.md), so it needs no server of its
own:

- Articles come from Supabase's PostgREST and Storage HTTP APIs with the anon key (`lib/services/api_client.dart`).
  Search calls the same `search_articles` database function as the API.
- Sign-in, sign-up and password reset use `supabase_flutter`. Likes are read and written with the signed-in user's token,
  and row-level security limits each user to their own.
- The 50 most recently opened articles are saved on the device (`shared_preferences`). When the server cannot be reached,
  the app shows those, with an offline banner. Search needs a connection.

The project URL and anon key are in `lib/config.dart`. Point them at your own project when you set one up; the anon key
is meant to be public, since row-level security is what protects the data.

## Run

Flutter stable (CI follows the stable channel; last verified on 3.47) with Android and/or iOS tooling for the platforms
you target (`./scripts/doctor.sh` or `flutter doctor` shows what is missing).

```bash
cd bharatverse_app
flutter pub get
flutter run -d chrome        # web; or any device or emulator from `flutter devices`
```

From the repo root, `./scripts/dev.sh` serves the web app on :8765 together with the API, and
`./scripts/run-device.sh [--release]` runs on a physical phone: natively, or, for an iPhone from Linux or Windows, as the
web app in the phone's browser ([details](../scripts/README.md)).

Password-reset emails link back to the app, so add the app's URL (for local web, `http://localhost:8765`) under
Supabase's Authentication > URL Configuration > Redirect URLs.

## Test

```bash
flutter test --coverage
../scripts/check_lcov_coverage.sh coverage/lcov.info 85 lib/main.dart    # CI's 85% coverage gate
dart format --output=none --set-exit-if-changed .
flutter analyze
```

## Layout

- `lib/screens/`: home, article, archive, search, likes, sign-in, forgot and reset password
- `lib/services/`: `api_client.dart` (articles and search), `likes_client.dart`, `article_cache.dart` (offline copies)
- `lib/state/`: `AuthState` and `LikeState`, the app's two `ChangeNotifier`s, provided with `provider`
- `lib/theme/` and `lib/widgets/`: the design tokens (colors, spacing, type) and the shared components built on them
- `test/`: mirrors `lib/`; services are tested against a fake HTTP client

The `android/`, `ios/` and `web/` folders hold the platform projects. To add desktop, run
`flutter create --platforms=linux,macos,windows .` from this folder.
