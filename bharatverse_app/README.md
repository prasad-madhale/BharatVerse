# Flutter app

The reader: today's article, an archive of earlier ones, search, likes and offline reading. It runs on Android, iOS and
the web.

## How it works

The app talks to Supabase directly, not through the [backend API](../backend/README.md), so it needs no server of its
own:

- Articles come from Supabase's PostgREST and Storage HTTP APIs with the anon key (`lib/services/api_client.dart`).
  Search calls the same `search_articles` database function as the API, and titles and tags are suggested while the
  reader types through `autocomplete_suggestions`.
- Sign-in, sign-up and password reset use `supabase_flutter`. Likes are read and written with the signed-in user's token,
  and row-level security limits each user to their own.
- The 50 most recently opened articles are saved on the device (`shared_preferences`). When the server cannot be reached,
  the app shows those, with an offline banner. Search needs a connection.

The project URL and anon key are in `lib/config.dart`. Point them at your own project when you set one up, or build
against another one with `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` (which is how
[`tools/local-stack`](../tools/local-stack/README.md) builds the app for its local stand-in). The anon key is meant to be
public, since row-level security is what protects the data.

Crash reports go to Sentry only from a build made with `--dart-define=SENTRY_DSN=...` (`lib/services/crash_reports.dart`);
the release workflow passes the `SENTRY_DSN` Actions secret, so tests, local runs and builds without the secret send
nothing. A report holds the error and its stack trace, the device model, OS, memory, locale and timezone, and a random
per-install id; no email, IP address, screenshot or session count. Its release is `<application id>@<version>+<build>`.

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

### End-to-end tests

`integration_test/` runs the real app on an Android emulator (not in CI). Several of its tests sign up, save and delete,
so they run against the local Supabase stand-in (`tools/local-stack`, which the emulator reaches at `10.0.2.2`), never
the hosted project. One command does it all:

```bash
../scripts/e2e.sh                                    # every integration_test/*_test.dart
../scripts/e2e.sh integration_test/smoke_test.dart   # or just some
```

It starts the stand-in, boots the emulator if none is running (AVD `bv_api35`), switches it to 3-button navigation,
runs each test with the stand-in's URL and key, prints what passed and failed, and stops the emulator it started. The
emulator and each build run in their own memory-capped scope: uncapped, an emulator beside a Gradle build ran a 14 GB
machine out of memory.

| Test | Covers |
|---|---|
| `smoke_test.dart` | sign up, read today's story, save it and find it in Library, search for it, sign out and back in, delete the account |
| `onboarding_test.dart` | no slide puts Skip under the status bar or the button under the navigation bar (#30) |
| `delete_account_test.dart` | deleting an account, and that it can no longer sign in |
| `era_browse_test.dart` | tapping an era card in Search lists that era's story |
| `report_article_test.dart` | a guest reports a story (`--dart-define=REPORT_NOTE=...` names the row to look for) |

### Before each release

On a phone, with the build that goes to Play:

- [ ] A fresh install, and an upgrade over the previous build (saved stories, reading history and settings survive).
- [ ] Light and dark, and the largest system text size.
- [ ] Offline: airplane mode after one launch online; the week's stories open.
- [ ] Sign up, sign out, sign in, a password reset email, and delete account.
- [ ] Report a problem on a story, and find the row in `article_reports`.
- [ ] `../scripts/e2e.sh` passes.
- [ ] The Play "What's new" text, written from the PRs merged since the last release.

## Layout

- `lib/screens/`: `app_shell.dart` (the tab-bar root), `onboarding_screen.dart` (first-run only), home, article,
  archive, search, likes, sign-in, forgot and reset password
- `lib/services/`: `api_client.dart` (articles and search), `likes_client.dart`, `article_cache.dart` (offline copies)
- `lib/state/`: `AuthState`, `LikeState`, `ThemeModeState` and `OnboardingState`, provided with `provider` except the
  latter (a plain constructor-injected dependency, not a `ChangeNotifier`)
- `lib/theme/` and `lib/widgets/`: the design tokens (colors, spacing, type -- `app_colors.dart` is a
  `ThemeExtension<AppColorTokens>` with Light and Dark palettes, read via the `context.colors` shorthand) and the
  shared components built on them
- `test/`: mirrors `lib/`; services are tested against a fake HTTP client

The `android/`, `ios/` and `web/` folders hold the platform projects. To add desktop, run
`flutter create --platforms=linux,macos,windows .` from this folder.

## App icon

`assets/icon/icon.png` (full-bleed) and `icon_foreground.png` (transparent, for Android's adaptive icon; kept within
the safe zone launchers may crop to) are the same saffron "B" mark as the web app's `web/icons/`, which this tool
does not touch. After changing either file, regenerate Android and iOS with:

```bash
dart run flutter_launcher_icons
```

It also rewrites `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` to a larger, minified idiom set
(adding pre-iOS-7 sizes this project doesn't target) and can reset an unrelated Xcode build setting
(`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`) to a wrong value -- check `git diff` on both after
running it.

## Onboarding images

`assets/onboarding/` holds one photo per first-run feature slide (`lib/screens/onboarding_screen.dart`), each
picked for that slide's period rather than pulled from live articles (onboarding runs before the reader has any).
All from Wikimedia Commons, credited by filename:

- `iron-pillar.jpg` -- [IRON PILLAR 4.jpg](https://commons.wikimedia.org/wiki/File:IRON_PILLAR_4.jpg), Cidsamir, CC BY-SA 4.0
- `ashoka-pillar-vaishali.jpg` -- [Ananda Stupa with Ashok lion pillar at vaishali, Bihar 03.jpg](https://commons.wikimedia.org/wiki/File:Ananda_Stupa_with_Ashok_lion_pillar_at_vaishali,_Bihar_03.jpg), Rohit Sharma, CC BY-SA 4.0
- `red-fort-independence.jpg` -- [Flag hoisting at Red Fort, Delhi on the occasion of 75th Independence day of India.jpg](https://commons.wikimedia.org/wiki/File:Flag_hoisting_at_Red_Fort,_Delhi_on_the_occasion_of_75th_Independence_day_of_India.jpg), Government of India, GODL-India
