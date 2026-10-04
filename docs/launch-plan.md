# Launch plan

The ordered work between today and BharatVerse 1.0 on Google Play, written so an agent session can take the next task
and finish it. [`roadmap.md`](roadmap.md) records what is built; this file records what is left before launch, and in
what order.

## Checkpoint, 2026-10-03

- **Code**: `main` = `origin/main` at `fde8f64`, PRs #26 to #29 merged. The Milestone 1 redesign is complete (theme and
  navigation, onboarding and auth, Home, Article, Library, Search, the Settings sheet).
- **Android builds**: `.github/workflows/android-release.yml` publishes a debug-signed APK as a GitHub Release
  (`apk-N`) on every app change to `main`. The app id is still `com.example.bharatverse_app`, version `0.0.1+1`. CI and
  local builds carry different debug keys, so switching between them needs an uninstall.
- **Pipeline**: locally, generation runs on OpenRouter's `google/gemma-4-31b-it`, and the critic's text and
  image-cohesion reviews on `qwen/qwen2.5-vl-72b-instruct`. The daily workflow still sets `LLM_PROVIDER=anthropic` and
  nothing for the critic or cohesion models. Its cron stays off on purpose.
- **Hosted content**: 6 articles. Reprocessed through the new pipeline: Mohenjo-daro (left with no images), Nalanda,
  Chauri Chaura. Not yet, because the OpenRouter credits ran out: Iron Pillar (`art_20260709_001`), Haldighati
  (`art_20260705_002`), Rani of Jhansi (`art_20260705_001`). Only Nalanda has an era ("427 CE - 1400 CE"); Gemma left
  it empty on the other two.
- **Hosted database**: `era`, `saved_articles`, search and autocomplete are applied (both answer, and the public key
  can no longer write `articles`). Its `search_vector` predates era, though, so no era is searchable and "Browse by
  era" finds nothing: re-run `2026-09-search-and-autocomplete.sql`, which drops and re-adds the column.
- **GitHub**: open issues #30 (onboarding slides ignore the bottom safe area, from an external tester on `apk-1`) and
  #2, #3, #5 (stale since 2025); PR #12 (unsigned iOS IPA workflow) undecided. Dependabot: 17 alerts (13 for crawl4ai
  0.4.24, and pytest and python-dotenv in both requirements files).
- **Untracked**: `ONBOARDING.md` at the root (see P8).

## Launch-ready means

BharatVerse 1.0 is on Google Play's production track (Android first), and:

1. **Store requirements**: a permanent app id, release signing with Play App Signing, app bundles with increasing
   version codes, privacy policy and terms URLs, account deletion in the app and on the web, the Data safety and content
   rating forms, and the closed test that new personal developer accounts must pass.
2. **Nothing fake**: every visible control works or is hidden. About shows the version, how articles are made, the
   licenses and where to get help.
3. **Content**: the bar in D8, and the daily pipeline running unattended for 7 days on the production config, alerting
   the owner when it fails.
4. **Accounts work on a phone**: sign up, sign in, reset a password through an emailed link that opens the app, delete
   the account.
5. **Operations**: crash reports reach the owner, the database is backed up and cannot pause, and LLM spend is capped.

Not in 1.0: iOS, a hosted web app, push notifications, Google sign-in and semantic search (see section C).

## How an agent works through this file

1. Read `AGENTS.md`, then this file. Take endpoint, service and Flutter class names from `design.md`.
2. Take the first task, in table order, whose status is `todo`, whose owner includes `agent`, and whose `Needs` are
   met: listed tasks `done`, listed decisions answered below. Never guess an open decision; skip the task instead.
3. Branch from an up-to-date `main`: `git switch -c <type>/<id>-<slug>`, for example `fix/l02-onboarding-safe-area`.
4. Keep to the task's scope, and write the test first where the behavior can be tested. If this file turns out to be
   wrong (a file moved, a fact changed), correct it in the same branch.
5. Before committing, run the checks AGENTS.md lists, one by one, in the existing venv (`.agent/venv`) with the Flutter
   SDK at `~/flutter/flutter`. Not `./build.sh`: even with `--check` it reinstalls both requirements files, which breaks
   that venv, and runs `playwright install --with-deps`, which needs sudo. Don't run the scraper, the daily pipeline or
   `integration` tests, and don't call a paid API, unless the owner asks in that session.
   Then prove the change end to end: for the app, an `integration_test` on the Android emulator plus screenshots
   (see `bharatverse_app/README.md`); for SQL, `tools/local-stack`. Never run the emulator and a build at once
   outside memory-capped scopes: together they ran this 14 GB machine out of memory.
6. Schema changes go in `schema.sql` plus a dated file in `backend/database/migrations/`, tested in
   `tools/local-stack/tests/`. Never change the hosted project; the task's person step applies the file.
7. Commit locally with a one-line conventional subject. In the same branch, set the task's status here to `done` (or
   `blocked: <reason>`) and update `roadmap.md` and the package README. Don't push or open a PR: the owner reviews each
   branch.
8. Stop and report when a task needs a secret, a dashboard, money, or a decision with no answer.

Any task can also go through `tools/agent-queue` once a planner session has written its exact change as a spec (see
that README); small mechanical ones such as L07 suit it best.

## Decisions for the owner

Write the answer in the last column. Agents skip tasks whose decision has none.

| ID | Decision | Recommendation | Answer |
|---|---|---|---|
| D1 | Android application id and iOS bundle id. Play never lets it change after the first upload. | `io.github.prasadmadhale.bharatverse`, or `<reversed domain>.bharatverse` if you will own a domain | |
| D2 | Hide controls with nothing behind them until they have it: "Continue with Apple" outside iOS, the notification toggles, "Download for offline", Home's category chips | Yes | |
| D3 | Publisher name, support email and country for the legal pages and the store listing | A dedicated support address, not a personal one | |
| D4 | The era list. One label per article, searched as typed, so no dates or dashes | Indus Valley, Vedic Age, Maurya Empire, Sangam Age, Gupta Empire, Early Medieval Kingdoms, Delhi Sultanate, Vijayanagara Empire, Mughal Empire, Maratha Empire, Colonial India, Freedom Struggle, Independent India | |
| D5 | When to turn on the daily cron | After 7 clean manual runs on the production config, with a scheduled backlog (L15) as a buffer; 03:30 UTC (09:00 IST) as drafted | |
| D6 | Crash reporting and analytics | Sentry crash reports only. No product analytics for 1.0: database counts and Play Console statistics cover launch | |
| D7 | Supabase plan | Free through the closed test, Pro before public launch (no pausing, daily backups) | |
| D8 | Content bar for public launch | 30 critic-approved articles live or scheduled, each with an era and images | |
| D9 | Audience age | 13 and over, which keeps the app out of Play's Families program | |

## Person checklist

Only the owner can do these. Longest lead time first.

- [ ] **P1 Google Play developer account.** $25 once, plus identity verification that can take days. A new personal
  account must run a closed test with at least 12 opted-in testers for 14 days in a row before it can publish to
  production (check the current numbers in Play Console; an organization account, which needs a D-U-N-S number, is
  exempt). Start recruiting testers now; the tester behind #30 is a good first one.
- [ ] **P2 Answer D1 to D9.**
- [ ] **P3 Signing (L08).** Create the upload keystore, back it up with its passwords somewhere other than this
  machine, add the secrets L08 lists, and opt in to Play App Signing on the first upload.
- [ ] **P4 GitHub Pages (L11).** Settings > Pages > Source: GitHub Actions. Review the legal text: the agent's draft is
  not legal advice.
- [ ] **P5 Supabase.** Set up custom SMTP: the built-in sender is for testing, tightly rate limited, and may only
  deliver to the project team's own addresses (check Authentication > Emails). Add L12's redirect URL. Apply each
  migration a task adds (L03, L04, L15) and re-run `2026-09-search-and-autocomplete.sql` for era search. Act on D7.
- [ ] **P6 OpenRouter.** Top up the credits and set a monthly limit. Add `OPENROUTER_API_KEY` to the repository's
  Actions secrets (L05).
- [ ] **P7 Play Console (L14).** Store listing, content rating, Data safety, target audience (D9), category, then the
  internal and closed test releases.
- [ ] **P8 Housekeeping.** Close #30 once L02 merges; close the stale #2, #3 and #5; merge or close PR #12. Delete
  `ONBOARDING.md` or fold what is right in it into `README.md`: AGENTS.md allows no other markdown at the root, and
  parts of it are wrong (it puts `scheduler.py` and `image_sourcing.py` in `scrapper/`, not `scrapper/scrapper/`).

## A. Closed test on Google Play

| ID | Task | Owner | Size | Needs | Status |
|---|---|---|---|---|---|
| L01 | Bring the roadmap up to this checkpoint | agent | S | | done |
| L02 | Onboarding respects safe areas (#30) | agent | S | | done |
| L03 | Delete account | agent, person | M | | done |
| L04 | Report a problem with an article | agent, person | M | | todo |
| L05 | Daily pipeline on the production config | agent, person | S | | todo |
| L06 | Atomic article save | agent | S | | todo |
| L07 | Permanent app identity and version | agent | S | D1 | todo |
| L08 | Release signing, app bundles and version codes | agent, person | M | L07 | todo |
| L09 | Hide controls with nothing behind them | agent | S | D2 | todo |
| L10 | About, how articles are made, licenses, help | agent | M | D3 | todo |
| L11 | Legal and support pages on GitHub Pages | agent, person | M | D3 | todo |
| L12 | Password reset opens the app | agent, person | M | L07 | todo |
| L13 | Controlled era list | agent | M | D4 | todo |
| L14 | Store listing assets | agent, person | M | L02, L09, L10 | todo |

Size: S is under an hour of agent time, M a few hours, L a day or more.

### L01 Bring the roadmap up to this checkpoint

`docs/roadmap.md` still describes 2026-09-25.
- The status date; phase 5 (the Settings sheet replaced the missing profile screen) and phase 6 (the APK release
  workflow).
- The pipeline paragraph: Gemma has now generated real articles (and left `era` empty on 2 of 3), the critic and the
  cohesion check run on Qwen2.5-VL, and the daily workflow stays on Anthropic until L05.
- "Needs a person": replace the Anthropic-credit reprocess note and the search-migration note with the checkpoint's
  state, and point to this file's person checklist rather than repeating it.
- Done: nothing in the roadmap contradicts the checkpoint.

### L02 Onboarding respects safe areas (#30)

On gesture-navigation phones the feature slides' dots and button sit under the system bar: only `_Splash` is inside a
`SafeArea`.
- `bharatverse_app/lib/screens/onboarding_screen.dart`: add `MediaQuery.viewPaddingOf(context).bottom` to the slide
  content's bottom padding (`EdgeInsets.fromLTRB(24, 26, 24, 40)`) and `.top` to Skip's `Positioned(top: 50)`. The
  photo stays full-bleed behind the system bars.
- Test: pump the slides with `viewPadding: EdgeInsets.only(top: 44, bottom: 48)` and assert that the button ends at
  least 48 px above the bottom of the screen and Skip starts below 44 px.
- Done: the test passes, and on a phone the button clears the navigation bar.

### L03 Delete account

Play requires deletion inside the app for any app that creates accounts, and a web route for people who have
uninstalled it (L11).
- `schema.sql` and `migrations/2026-10-delete-account.sql`: `delete_my_account()`, `SECURITY DEFINER` with a pinned
  `search_path`, deleting the `auth.users` row for `auth.uid()`, executable by `authenticated` only. The `users`,
  `likes` and `saved_articles` rows go with it through their `ON DELETE CASCADE` keys.
- `tools/local-stack/tests/`: a user deletes only themselves, their likes and saves go with them, and `anon` cannot call
  it.
- App: `AuthState.deleteAccount()` calls it, signs out, and clears the queued likes and saves (`PendingLikes`,
  `PendingSaves`). A "Delete account" row in the Settings sheet asks for confirmation in a dialog that says what is
  deleted.
- Person: apply the migration (P5).
- Done: tests pass; on the local stack, signing up, liking, saving and deleting leaves no row for that user.

### L04 Report a problem with an article

Lets readers flag a factual error, a wrong image or offensive text without leaving the app. Google Play's
AI-generated content policy asks for in-app flagging; confirm whether it applies to this app while filling in the Play
forms, but the feedback is worth having either way.
- `schema.sql` and a migration: `article_reports` (article id, user id or null, reason `factual`, `image`, `offensive`
  or `other`, an optional note of at most 1,000 characters, created at). `anon` and `authenticated` may insert, with a
  user id that is their own or null, and nothing else.
- App: "Report a problem" at the end of an article opens a sheet with the reasons and a note field, sends it through
  `ApiClient`, and thanks the reader. Offline, it says the report could not be sent.
- Person: apply the migration (P5) and read reports in the Supabase table editor (say so in the roadmap).
- Done: SQL tests for the insert-only rights, a widget test for the sheet, a client test for the request.

### L05 Daily pipeline on the production config

- `.github/workflows/daily-pipeline.yml`: `LLM_PROVIDER: openrouter`, `OPENROUTER_API_KEY` from secrets, and
  `CRITIC_LLM_PROVIDER`, `CRITIC_LLM_MODEL`, `IMAGE_COHESION_LLM_PROVIDER` and `IMAGE_COHESION_LLM_MODEL` as in
  `.env.example`. Without them the cohesion check falls back to Ollama, which CI lacks, so no image is checked. Keep
  the schedule commented out (AGENTS.md). Move to `actions/setup-python@v5`.
- On failure, open or comment on a GitHub issue labelled `pipeline-failure` with the run's link
  (`permissions: issues: write`): the alerting requirement 11.5 asks for. `scrapper_main.py` already exits non-zero
  when it publishes fewer articles than asked.
- Make `max_tokens` for generation and the critic configurable (both are 16,000). OpenRouter reserves credit for the
  whole `max_tokens` up front, which is how a low balance failed with "can only afford 14720".
- Person: add the secret (P6), check the `SUPABASE_*` ones, run the workflow by hand and read the article.
- Done: tests for the new settings; the workflow parses (`actionlint`, if available).

### L06 Atomic article save

`ArticleService.save_article` overwrites the Storage blob, then upserts the row. When the row write fails, the two
disagree: that is how Mohenjo-daro lost its images during the reprocess.
- Upload to a new content-addressed path (`articles/<date>/<id>-<first 12 hex of sha256>.json`), upsert the row with
  that `content_file_path`, then delete the previous blob, logging rather than failing if that delete fails. A failed
  row write leaves the old row on its old, intact blob. The app reads `content_file_path`, so it needs no change.
- Wire tests (`backend/tests/wire.py`): the order of the requests, and that a failed upsert never deletes the old blob.
  Drop the non-atomic caveat from `scrapper/tests/scrapper/test_reprocess_articles.py`.

### L07 Permanent app identity and version

- Android: `namespace` and `applicationId` from D1 in `bharatverse_app/android/app/build.gradle.kts` (drop the TODO),
  `MainActivity.kt` moved from `kotlin/com/example/bharatverse_app/` to the new package's path with its `package` line
  fixed, and `android:label="BharatVerse"` in `AndroidManifest.xml`.
- iOS: every `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj/project.pbxproj` (the test target keeps its
  `.RunnerTests` suffix), and `CFBundleDisplayName` and `CFBundleName` "BharatVerse" in `ios/Runner/Info.plist`.
- `pubspec.yaml`: `version: 1.0.0+1`; CI sets the build number (L08). The Dart package keeps its name,
  `bharatverse_app`, so imports don't change.
- The new id installs as a separate app: testers uninstall the old one.
- Done: `grep -rn "com.example" bharatverse_app/android bharatverse_app/ios` finds nothing, and `aapt2 dump badging` on
  a release APK shows the new package and the label "BharatVerse".

### L08 Release signing, app bundles and version codes

- `build.gradle.kts`: a `release` signing config read from `android/key.properties` (local) or the environment (CI:
  `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`). With neither, fall
  back to debug signing, so anyone can still build. Git-ignore `key.properties`, `*.jks` and `*.keystore`.
- `android-release.yml`: when the `ANDROID_KEYSTORE_BASE64` secret is set, decode it to a temporary file; build the
  `appbundle` and the `apk` with `--build-number=${{ github.run_number }}`, since Play needs a higher version code on
  every upload (add an offset if the workflow is ever replaced); attach both; say in the release notes which key signed
  them, and fix the notes' stale reference to `build.gradle`.
- `bharatverse_app/README.md`: how to make the keystore
  (`keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`) and which
  secrets to add. Note that Play re-signs its installs with its own key, so a GitHub APK and a Play install cannot
  update each other.
- Person: P3.
- Done: a run with the secrets produces an app bundle and an APK signed with the upload key (`apksigner verify
  --print-certs`), with the run number as version code; a run without them still succeeds, debug-signed.

### L09 Hide controls with nothing behind them

Per D2.
- `auth_screen.dart`: show "Continue with Apple" only on iOS, and only in a build made with
  `--dart-define=APPLE_SIGN_IN=true`.
- `settings_sheet.dart`: hide the three notification toggles and "Download for offline"; keep their `SettingsState`
  fields for later (L18 may bring the offline switch back).
- `home_screen.dart`: hide the category chips until L28. They filter the 5 loaded articles by hard-coded words, so most
  show nothing.
- The About card's "Coming soon" rows: L10 replaces them; hide them too if L10 is not done first.
- Update "Not built" in the roadmap; tests assert the hidden controls are absent.

### L10 About, how articles are made, licenses, help

- Add `package_info_plus`. The Settings sheet's About card shows the version and build number, and opens:
  - "How articles are made": an LLM writes each story from Wikipedia and other public sources, a second model reviews
    it for grounding, neutrality and fitting images, every article cites its sources, image credits show under each
    image (`lib/widgets/article_image.dart`), and mistakes are still possible (report them, L04).
  - The privacy policy and terms: L11's URLs, kept in one constant, opened with `url_launcher`.
  - Open-source licenses: `showLicensePage` (with the font licenses, if L19 lands first).
  - Help and feedback: a `mailto:` to the D3 support address with the app version filled in.
- Done: `grep -rn "Coming soon" bharatverse_app/lib` finds nothing; widget tests cover each row.

### L11 Legal and support pages on GitHub Pages

- `site/`: `index.html` (what BharatVerse is, and the store link once live), `privacy.html`, `terms.html`,
  `delete-account.html`, `support.html`, and one stylesheet in the app's palette. Plain HTML with system fonts, no
  trackers.
- `.github/workflows/pages.yml`: deploy `site/` when `site/**` changes (`actions/upload-pages-artifact`,
  `actions/deploy-pages`).
- The privacy policy describes what the app actually does: the email and password Supabase Auth holds; likes and saves;
  preferences and reading history kept on the device; crash reports once L17 lands; fonts fetched from Google until L19
  lands; no ads, no selling, no tracking; where Supabase hosts the data (the project's region); deletion in the app
  (L03) or by emailing support, which the owner carries out in the Supabase dashboard; not directed at children under
  13 (D9); the contact from D3.
- Terms: articles are AI-written and may contain mistakes; how sources are credited and licensed (Wikipedia text is
  CC BY-SA, and each image shows its own license); no warranty.
- Person: P4, and review the text.
- Done: the pages render locally; after P4 they are live under `https://prasad-madhale.github.io/BharatVerse/`.

### L12 Password reset opens the app

On a phone the reset link has nowhere to go: `AuthState` sets a redirect only on the web.
- Redirect native builds to `<app id>://reset-callback` (L07), and rename `_resetRedirectTo` to `_authRedirectTo`,
  since Apple sign-in uses it too. Register the scheme: an `intent-filter` (VIEW, DEFAULT and BROWSABLE, with that
  scheme and host) on `MainActivity`, and `CFBundleURLTypes` on iOS. `supabase_flutter` picks the link up and
  `RecoveryGate` shows the new-password form. Check app_links' notes on Flutter's built-in deep linking, which may need
  turning off.
- Person: add the URL under Supabase's Authentication > URL Configuration > Redirect URLs, set up custom SMTP (P5), and
  try a real reset on a phone, both with the app closed and with it open.
- Done: a unit test for the native redirect; on a phone, "Forgot password?", then the email's link, opens the app on
  the new-password form, and the new password signs in.

### L13 Controlled era list

Only 1 of the 6 hosted articles has an era, and that one ("427 CE - 1400 CE") is a date range that search reads
poorly.
- The D4 list, in chronological order, in one place in `common/`, shared by the generator and the validator.
- `scrapper/scrapper/article_generator.py`: the generation and revision prompts pick exactly one label from it.
- `scrapper/scrapper/content_validator.py`: reject an empty or unknown era, so the existing retry and revision paths fix
  it instead of publishing without one.
- `scrapper/reprocess_articles.py`: `--ids` to redo only the named articles (today it redoes every one), and
  `--eras-only` to assign an era from the title and summary with one small LLM call each, so existing articles need no
  full reprocess. The owner runs it, since it costs money.
- Person: re-run `2026-09-search-and-autocomplete.sql` on the hosted project (P5), so era is in `search_vector`.
- Done: tests for the prompt, the validator and both flags; after the backfill and the migration, tapping an era card
  on a phone lists its articles.

### L14 Store listing assets

- Screenshots of a release build in light and dark (Home, Article, Library, Search, Settings), taken at 1080x2400 on an
  emulator or the phone (`adb exec-out screencap -p`; on a foldable with several displays, pass `-d <display id>`), a
  1024x500 feature graphic, and the 512x512 icon from `assets/icon/`, all under `docs/store/`.
- `docs/store/listing.md`: the name, a short description (80 characters at most), the full description (4,000 at
  most), the category (Books & Reference or Education), and Data safety and content rating answers taken from L11's
  privacy policy.
- Person: review, upload and fill in the forms (P7).

## B. Public launch

| ID | Task | Owner | Size | Needs | Status |
|---|---|---|---|---|---|
| L15 | Scheduled publishing and takedown | agent, person | L | L13 | todo |
| L16 | Launch content | person, agent | M | L05, L06, L13, L15 | todo |
| L17 | Crash reporting | agent, person | M | D6 | todo |
| L18 | Offline: the last 7 days | agent | M | | todo |
| L19 | Bundle the fonts | agent | S | | todo |
| L20 | Scraper dependencies and politeness | agent | L | | todo |
| L21 | Python test pins | agent | S | | todo |
| L22 | Accessibility pass | agent | M | | todo |
| L23 | Release checklist and smoke test | agent | M | L08 | todo |

### L15 Scheduled publishing and takedown

A reviewed backlog means a failed day goes unnoticed by readers, and a takedown means a bad article can go quickly.
- `articles.status` (`published` by default, or `withdrawn`), and the row's `date` is the day it goes live. The public
  read policy becomes `status = 'published'` and `date` on or before today in IST, so the app needs no change: RLS
  filters Home, the archive, eras and search (`search_articles` runs with the caller's rights).
- Suggestions: a `SECURITY DEFINER` trigger rebuilds `search_suggestions` from every row, which would leak scheduled
  titles. Build it from visible rows only, and rebuild it when the day turns (a `pg_cron` job, or the daily run calling
  the rebuild).
- Backend: its service-role client bypasses RLS, so add the same filter to its public article queries.
- Pipeline: `scrapper_main.py --publish-on YYYY-MM-DD`, and `--backlog N` to fill the next free dates.
- Storage blobs stay public, so a scheduled article is readable by anyone who guesses its path. Acceptable; note it in
  the roadmap.
- Person: apply the migration (P5); withdraw an article by setting its `status` in the table editor.
- Done: local-stack tests for visibility by date and status and for suggestions, wire tests for the backend filter,
  and tests for the pipeline's date assignment.

### L16 Launch content

- Person: P6, then the three articles not yet reprocessed (`python scrapper/reprocess_articles.py --ids ...`, L13),
  Mohenjo-daro's images (`python scrapper/backfill_images.py`) and the era backfill (L13).
- Then generate the backlog until D8's bar is met, reading each article in the app, or a sample, before its date.
  After 7 clean days, decide D5.
- Agent, when the owner asks in a session: run those commands, report each critic outcome and the cost, and flag the
  rejects.

### L17 Crash reporting

Per D6 (recommended: Sentry).
- `sentry_flutter`, started only in a build made with `--dart-define=SENTRY_DSN=...`, so tests and local runs send
  nothing; `sendDefaultPii` off; the release named after the version and build number.
- The release workflow passes the DSN from a secret.
- Update the privacy policy (L11) and the Data safety draft (L14).
- Person: create the Sentry project and add the secret.

### L18 Offline: the last 7 days

Requirement 8.3 asks for at least the last 7 days of articles offline; the app caches only what was opened, and Home
loads 5.
- When online at start-up and on refresh, cache the content of every article dated in the last 7 days through
  `ArticleCache` (its 50-article capacity is plenty); eviction stays oldest first (8.4).
- Either bring "Download for offline" back (L09 hides it) as the switch for this, on by default, or leave it hidden;
  record the choice in the roadmap.
- Done: a test with a fake client shows 7 days cached after start-up and Home showing them offline.

### L19 Bundle the fonts

`google_fonts` downloads Newsreader and Work Sans from Google the first time they are used: a first launch offline
shows fallback fonts, and the download shares the reader's IP address with Google, which the privacy policy would have
to say.
- Add the weights `lib/theme/app_typography.dart` uses as files under `assets/google_fonts/` (`google_fonts` finds them
  by name), set `GoogleFonts.config.allowRuntimeFetching = false` in `main.dart`, and add the fonts' OFL to
  `LicenseRegistry`.
- Done: tests pass; a first launch in airplane mode shows the right fonts.

### L20 Scraper dependencies and politeness

- Upgrade `crawl4ai` from 0.4.24 to a release that fixes the Dependabot alerts (0.9.0 or later), adapting
  `scrapper/scrapper/sources/base.py` (`BrowserConfig`, the `chrome_channel` workaround, the markdown result); or fetch
  over plain HTTP where no browser is needed (Wikipedia's text already comes through its API).
- One descriptive User-Agent for every request, defined once: the sources, `wikipedia.set_user_agent` (today it
  points at `github.com/bharatverse`, not this repository) and `image_sourcing.USER_AGENT`.
- Respect robots.txt (requirement 1.5) in `ContentSource.extract` or `_scrape_url`, through
  `WebScraper.check_robots_txt` with that agent. Fetch robots.txt with the descriptive agent too: Wikipedia answers
  Python's default one with 403, which `RobotFileParser` reads as "disallow everything".
- Done: unit tests with stubbed robots.txt responses; the scraper's `integration` tests pass in a run the owner
  approves (network only, no LLM spend).

### L21 Python test pins

`backend/` and `scrapper/` pin different `pytest` (7.4.4 and 7.4.3) and `pytest-asyncio` (0.23.4 and 0.21.1)
versions, so AGENTS.md's one-line install fails (`ResolutionImpossible`), and Dependabot flags `pytest` and
`python-dotenv`.
- The same versions in both files: `pytest` 9.0.3 or later, a `pytest-asyncio` that supports it, and `python-dotenv`
  1.2.2 or later. Keep `fastapi==0.109.0` and `supabase==2.9.0`.
- Fix the tests that relied on the old asyncio event-loop behavior, if any.
- Done: `./build.sh --check` passes in a fresh venv made with AGENTS.md's install line.

### L22 Accessibility pass

- Labels on the icon-only controls (the glass back button, bookmark, heart, the Search button, era cards), tap targets
  of at least 48 dp, system text scaling up to 200% without overflow on Home, Article and Settings, and muted text at
  4.5:1 contrast in both themes.
- Tests: `androidTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline` on the main screens.

### L23 Release checklist and smoke test

- An `integration_test/` happy path (onboarding, Home, open an article, sign in and save it, Library) that runs
  against `tools/local-stack` on an emulator or a phone; how to run it goes in `bharatverse_app/README.md`.
- A per-release checklist in the same README: a fresh install and an upgrade from the previous build, light and dark,
  offline, sign up, sign in, sign out, reset, delete, and the Play "What's new" text.

## C. After launch

| ID | Task | Owner | Size | Needs | Status |
|---|---|---|---|---|---|
| L24 | Native splash screen and Android toolchain upgrades | agent | S | | todo |
| L25 | Share an article | agent | M | L11 | todo |
| L26 | Google sign-in | agent, person | M | | todo |
| L27 | iOS release | person, agent | L | | todo |
| L28 | Home categories from real data | agent | M | | todo |
| L29 | Topic de-duplication beyond the last 200 titles | agent | S | | todo |

- **L24**: `flutter_native_splash` in the parchment and night colors; Gradle, the Android Gradle plugin and Kotlin
  raised to the versions Flutter's build warnings ask for.
- **L25**: `share_plus`, sharing the title, the summary and a link. The link needs a target: a per-article page on the
  L11 site that reads the article through the public API, or the store listing until one exists.
- **L26**: the person creates the Google OAuth clients (Android, with the SHA-1 of both the upload and the Play app
  signing keys, and a web client for Supabase) and enables the provider; the agent adds `google_sign_in` and
  `signInWithIdToken`. Shipping it on iOS also requires Sign in with Apple or an equivalent (App Store guideline 4.8).
- **L27**: decide PR #12, join the Apple Developer Program, sign in CI, answer App Privacy, ship through TestFlight, and
  add Sign in with Apple if L26 ships there. L07 and L12 already cover the bundle id and the URL scheme.
- **L28**: a `category` field from a controlled list, like era (or the most common tags), and the chips back on Home.
- **L29**: topic selection excludes only the last 200 titles (`ArticleService.list_recent_titles`). Store each
  article's source topic (its Wikipedia title) and exclude by that.

Then the design handoff's later milestones: M2, a personalization questionnaire in onboarding and a weekly quiz; M3,
person and topic hubs, and listen and watch versions of a story (the continue-reading bar becomes a mini player); M4
and later, a chat about an article that answers with citations, and an interactive map. Also open: push notifications
(which would give the hidden notification toggles a purpose), semantic search with pgvector, and a hosted web app.
