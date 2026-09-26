# Roadmap

Status and sequencing. [`design.md`](design.md) is the architectural reference and [`requirements.md`](requirements.md)
the requirements; this file records what is built, where it differs from the design, and what is left. Status as of
2026-09-25.

## Phases

| Phase | Scope | Status |
|---|---|---|
| 0 | Vertical slice: scrape, generate, store, serve, display | Done, verified live |
| 1 | Auth: Supabase email and password, password reset | Done, verified live; OAuth not started |
| 2 | Search: full-text, then autocomplete, then semantic | Full-text and autocomplete done; semantic undecided |
| 3 | Likes and offline reading | Done |
| 4 | Validator, editorial critic, scheduler and daily automation | Done, verified live; the cron is off on purpose |
| 5 | Remaining mobile screens and polish | Done except a profile screen |
| 6 | Deployment | Backend Dockerfile done; hosting, scheduler and app store prep not started |

"Verified live" means run against the real project and a real browser; the later features were verified against a local
Postgres and PostgREST running `schema.sql`, with the hosted project unchecked.

## What is built

- **Pipeline** (`scrapper/`): an LLM proposes topics that are not yet published; Wikipedia, archive.org, New World
  Encyclopedia and the Indian Culture Portal are scraped (the Portal's search sits behind bot-detection that blocks
  plain HTTP requests, so it goes through a real browser session, retried with backoff since that interaction is
  measurably flaky; most of its catalog is archival-record metadata with no body text, so only results with real
  content are kept); an LLM writes the article; `ContentValidator`'s structural checks (length, sections,
  citations) gate it, `image_sourcing.py` attaches up to 3 images (1 featured, 2 inline) from the topic's own
  Wikipedia page (already curated for relevance, since topics are chosen to match real Wikipedia titles), falling
  back to a Wikimedia Commons keyword search -- vision-checked for relevance, unlike the Wikipedia-sourced images --
  when that page has too few, then `ArticleCritic` reviews the draft and its images as an editor would -- grounding
  in the source material (the check specific to an AI-from-scraped-sources pipeline), citation relevance,
  neutrality, contested claims stated as settled fact, structure, and whether every image (not only the featured
  one) genuinely fits the piece, checked with a local model since it runs once per image, per round -- and
  `ArticleGenerator.revise_article` addresses a text issue while a full image re-source (excluding whatever was
  just rejected) addresses a cohesion one, both in the same round if needed, up to `CRITIC_MAX_ROUNDS` (4, i.e. up
  to 3 revisions) review/revise cycles before falling back to a fresh generation. Closes requirements 2.5, 5.5 and
  10.3, which `ContentValidator` alone could not (it "cannot verify factual accuracy", by its own docstring). Only
  Public Domain/CC0/CC-BY/CC-BY-SA images at least 500px wide are used, downloaded and re-hosted in Storage, never
  hotlinked; a sourcing failure publishes with no images rather than losing an otherwise-good article. Set
  `CRITIC_ENABLED=false` or `IMAGE_SOURCING_ENABLED=false` to skip either for a cheap local run. `backfill_images.py`
  attaches images to already-published articles that predate `image_sourcing.py`; `reprocess_articles.py` re-runs
  an already-published article through the current critic and generator (grounding and image cohesion both), for
  ones published before a critic or prompt fix landed -- it only overwrites when the critic ends up approving, so a
  rejected reprocess just leaves the article as it was. The service-role client publishes the result. A generation
  failure retries with backoff, and one bad topic never stops the batch. The daily GitHub Actions workflow runs on
  demand only: its schedule stays commented out until the output is trusted over more unattended runs, so do not
  enable it without deciding that first. The daily workflow uses Claude Sonnet 5; a local run defaults to Gemini.
  Groq's free tier, and two local Ollama models tried for generation and review (`qwen3.5:9b`, `qwen2.5:7b-instruct`),
  were rejected for weak word-count adherence -- Groq and `qwen2.5:7b-instruct` undershot, `qwen3.5:9b` overshot by
  as much as 65% in a real run; local inference stays scoped to the free, per-image cohesion check
  (`IMAGE_COHESION_LLM_PROVIDER`), not generation or the text critic. An `openrouter` provider (any model it routes
  to; `common/llm_provider.py` reuses the `openai` SDK against OpenRouter's OpenAI-compatible API, including its
  OpenAI-style vision message format) was added and wired to `google/gemma-4-31b-it` for generation -- confirmed
  reachable with a live key and response (a trivial round-trip, not a full article), but not yet run through
  generation to check word-count adherence the way Groq/Ollama were. `LLMProvider` also gained a `model` constructor
  override (alongside the existing `provider` one), and `ArticleCritic` gained matching `CRITIC_LLM_PROVIDER`/
  `CRITIC_LLM_MODEL` settings (mirroring `IMAGE_COHESION_LLM_PROVIDER`, which also gained an `_LLM_MODEL` pair) --
  both the critic's text review and the image-cohesion check are wired to OpenRouter's `qwen/qwen2.5-vl-72b-instruct`
  -- a different, larger vision model than generation's Gemma, chosen for those two review roles specifically --
  each confirmed with a real call (a text round-trip, and a vision call that correctly named a test shape's color).
  One OpenRouter API key authenticates the account and covers every model it routes to, not just one. Claude Sonnet 5 runs
  adaptive thinking by
  default, which shares `max_tokens` with the response and had caused the critic and revision calls to occasionally
  return empty text on long prompts; both now pass `effort="medium"` to cap thinking depth, and their prompts use
  XML-tag structuring with source material placed first, per Anthropic's current prompt-engineering guidance.
- **API** (`backend/`): articles (`daily`, by id, paged list), full-text search, sign-up, login and logout, likes,
  rate limiting and JSON request logs.
- **App** (`bharatverse_app/`): home with recent articles, article, archive, search with highlighted terms (matched by
  stem with `porter_2_stemmer`, the same algorithm Postgres's search uses, so "empires" marks "Empire" too), likes
  (queued in `PendingLikes` and sent once the server can be reached, so a tap while offline is not lost),
  sign-in and password reset, offline reading of the 50 most recently opened articles. It reads Supabase directly, so it
  works on a real phone without a local server. The design system is "Vintage Broadsheet" (parchment, saffron and India
  green; Newsreader and Work Sans) in `lib/theme/` and `lib/widgets/`. The Android, iOS and web launcher icons are the
  same saffron "B" mark (`bharatverse_app/assets/icon/`, `flutter_launcher_icons`; see its README).
- **App redesign, done** ("Milestone 1", an Apple Podcasts-inspired reimagine from a Claude Design handoff): all
  four phases (theme + navigation, onboarding + auth, Home/Article/Library/Search, Settings sheet) are done.
  `lib/theme/app_colors.dart`/
  `app_typography.dart` are now a `ThemeExtension<AppColorTokens>` with full Light and Dark ("Night Edition")
  palettes, resolved via the `context.colors` shorthand; `ThemeModeState` (Provider + `SharedPreferences`, same
  `.open()` factory convention as `ArticleCache`/`PendingLikes`) holds the reader's Light/Dark/System choice,
  exposed via the Settings sheet's Appearance rows -- it defaults to System. `AppShell` replaces the old push-only
  root with an `IndexedStack` of Today/Library tabs under a floating glass-blur tab bar and a separate Search
  button (`GlassSurface`, `lib/widgets/glass_surface.dart`). `OnboardingScreen` (splash + 3 feature slides, shown
  once per install via `OnboardingState`) uses its own bundled photos (hand-picked from Wikimedia Commons after a
  live-fetch-from-articles attempt, and the mockup's own stock art, both looked underwhelming) -- see "Deviations"
  below. `AuthScreen` is a bespoke rebuild (rounded pill fields and buttons, a "Continue with Apple" entry point, a
  guest "Not now -- just browse" path when reached from onboarding) rather than the shared `AuthFormPage`, which
  `ForgotPasswordScreen`/`ResetPasswordScreen` still use, lightly restyled (sentence-case titles, pill
  fields/buttons). `era` (a short LLM-generated period label, e.g. "Gupta Empire") is a real field now: the
  generation/revision prompts ask for it, `common.models.Article`/`ArticleRecord`/the Flutter `Article` model all
  carry it (defaulting to `""`, so it needs no backfill to keep old rows and test fixtures working), and
  `schema.sql`/`2026-09-era-field.sql` add the column. It is also woven into full-text search now: `search_vector`
  weights era the same as tags (`'B'`), so searching an era's exact label (e.g. from the "Browse by era" grid
  below) ranks like any other tag match -- `2026-09-search-and-autocomplete.sql` (not yet run against the hosted
  project; see "Needs a person") carries this directly, since it had not been run there either when this landed.
  Save/bookmark is a full second vertical slice paralleling Likes exactly, not a
  reuse of it: `saved_articles` table, `SaveService`, `/articles/{id}/save` + `/users/me/saves` routes on the
  backend; `SavesClient`/`SaveState`/`PendingSaves` in the app, registered in `main.dart` right after the
  equivalent Likes classes. `HomeScreen` ("Today") is rebuilt: a masthead (date, an avatar button -- see the
  Settings sheet, below), category chips that filter the loaded articles by tag
  or era, a rounded-artwork featured card, and an "Earlier this week" list -- both card sizes moved into
  `ArticleCard`, which now also carries the save-toggle bookmark button used everywhere it appears (Home, Archive,
  Search, Library). The old `AppHeader` (and the icon-only `LikeButton` it and the article screen used) are
  deleted, superseded by the masthead and by the article screen's own labelled Save/Like pills. `ArticleDetailScreen`
  is rebuilt around those two pills, a floating glass back button, and a plain (not overlaid) date/read-time/era
  byline; it has no share button yet (no share package, and no defined per-article URL to share), which
  "Not built" below tracks. `LikedArticlesScreen` (a standalone "your likes" list, opened from a header icon) is
  deleted along with that icon: the redesign has no such screen, only the per-article Like toggle. In its place,
  the Library tab is a real `LibraryScreen` -- a "Saved" section (`SaveState`/`SavesClient`, mirroring how Likes
  load) and a "Recently read" section backed by a new `ReadingHistory` (`SharedPreferences`-backed like
  `ArticleCache`, but device-local rather than per-user, since it is reading history, not an account record);
  `openArticle()` records into it for every screen that opens an article. The mockup's per-row "remove from saved"
  button reuses `SaveButton`; recently-read rows have no action, matching the mockup. `ReadingHistory` is now a
  `ChangeNotifier` (unusual for this app's local-only services, see its own doc comment) specifically so `AppShell`'s
  continue-reading bar -- a floating glass pill above the tab bar, reopening the most recently read article --
  updates the moment any screen opens a new one, without every one of them (Home, Library, Search, era cards) having
  to signal `AppShell` itself. It shows the article's own reading time rather than the design's fabricated
  "N min left": there is no reading-progress tracking to make a real *remaining* estimate. `SearchScreen` is
  restyled to match (a borderless rounded search field with a leading icon and a clear button, replacing the old
  bordered `AppInput`; the submit action is still a real, separate `AppButton` -- small and pill-shaped now -- since
  the app's debounced-autocomplete-then-submit search is real and asynchronous, unlike the mockup's instant
  client-side filter) and gains a "Browse by era" grid (`ApiClient.getEras`, a lightweight metadata-only fetch of
  the distinct eras among recent articles, each with a representative real article image -- not the mockup's
  bundled stock photos) shown whenever nothing has been searched for yet; tapping an era searches its exact label.
  Tapping the masthead's `AccountAvatar`
  while signed in opens `SettingsSheet` (a modal bottom sheet, not a pushed screen) instead of signing out directly;
  signed out, it still opens `AuthScreen`. The sheet shows the real signed-in email under a generic "Your account"
  label rather than the mockup's fake "Reader" display name, since the app has no real name concept. Its Appearance
  rows read/write the existing `ThemeModeState`, so the Light/Dark/System choice from Phase 1 is now reachable from
  the UI. A new `SettingsState` (`ChangeNotifier`, `SharedPreferences`-backed, same `.open()` factory convention)
  holds the rest: a `TextSize` enum (small/medium/large, 16/18/21pt) that `ArticleDetailScreen`'s body text actually
  resizes to (read defensively -- `TextSize.medium` when nothing registered a `SettingsState`, so tests that don't
  care about text size don't need to wire one up, the same tradeoff as `ReadingHistory` above); three notification
  toggles (daily story, weekly digest, product news); and an offline-download toggle. Both are documented in "Not
  built" below, since neither does anything beyond persisting a preference.
- **Search**: `search_articles` in `schema.sql` ranks a weighted `search_vector` over title, tags, era and summary
  (not article bodies, which live in Storage), so a tag- or era-only match is found too. PostgREST's `text_search`
  takes a column name, not an expression, which is why the vector is a stored column with a GIN index. A tag like
  `covid-19` is indexed as typed and with the hyphen read as a space, so both `covid-19` and `covid 19` find it.
- **Autocomplete**: `search_suggestions` holds every phrase a reader may type (the parts of each title split at a colon
  or dash, as they are and without a leading "the", "a" or "an", and the tags with hyphens read as spaces) with the
  number of articles that carry it. A phrase is kept only if searching for it finds the article it came from, so every
  suggestion leads to a result, and it is at most 200 characters. A trigger rebuilds the table after every change to
  `articles` (about 0.4 s at 2,000 articles, which suits one article a day) and a failed rebuild only warns, so it never
  stops a write. `autocomplete_suggestions` returns the ones that start with what was typed, the phrases more articles
  carry first, then tags before titles, then shorter ones, at most 20; a lookup takes about 3 ms through PostgREST at
  2,000 articles (about a millisecond in the database), against the design's 50 ms. The app asks 200 ms after typing
  pauses and shows the suggestions in place of the results, which stay mounted underneath.

## Next

1. **Semantic search**: the placeholder `article_embeddings` table was removed. It needs pgvector and an embeddings
   provider, and is worth deferring past the rest of the MVP.
2. **Deployment** (Phase 6): `backend/Dockerfile` is done (built from the repo root, since it copies `common/` too;
   not tried on a real Docker daemon here). Left: a hosting choice, the scheduler on that host, and app store
   preparation (icons, signing, review lead time, especially on iOS).

## Needs a person

- **Hosted Supabase project.** Apply schema changes by hand, as a file in `backend/database/migrations/`. The `era`
  column (`2026-09-era-field.sql`) and the `saved_articles` table (`2026-09-saved-articles.sql`) the app redesign
  added have been run there. Still needed: `2026-09-search-and-autocomplete.sql`, which lacked the `search_vector`
  column and the `search_articles` function as last checked, and has the earlier, unused `search_suggestions` and
  `article_embeddings` tables. Running it adds search (now including `era` in `search_vector`, so the app's
  "Browse by era" grid returns real results there too), replaces those tables with the new suggestions and its
  trigger, takes the write rights off `articles` from the public key, and can be run twice. Until then search fails
  there and the app shows no suggestions. Supabase
  permanently deactivates free projects paused for over 90 days, which is how the first project was lost: restore a
  paused one promptly. Add the app's URL under Authentication > URL Configuration > Redirect URLs for password reset,
  and keep email confirmation off, or sign-up returns no session.
- **OAuth.** Google and Facebook app registration has days of review lead time and has not been started.
- **Apple Sign-In.** The app redesign's "Continue with Apple" button calls `AuthState.signInWithApple`, which is
  wired to Supabase's real `signInWithOAuth(OAuthProvider.apple)` call path, but it cannot complete until the Apple
  provider is configured on the Supabase project (an Apple Developer account, a Services ID, and the matching
  entitlements) -- also days of lead time, and not started.
- **Hosting**, the daily cron, and app store accounts.
- **Backfill images on the hosted project.** Every article published before `image_sourcing.py` landed has no
  `image_url`. Run `python scrapper/backfill_images.py` against the hosted project's credentials once.
- **Reprocess the hosted project's existing articles.** They were written before this session's critic fixes
  (image cohesion, the `effort`/prompt-reliability fix, `CRITIC_MAX_ROUNDS` raised to 4) landed. Run
  `python scrapper/reprocess_articles.py` against the hosted project's credentials once there is Anthropic API
  balance to spend -- a run against all 6 on 2026-09-24 exhausted the account's credit balance partway through
  (`anthropic.BadRequestError: ... credit balance is too low`), so add credits before retrying. The one article
  that did get reviewed before that (Mohenjo-daro) was correctly rejected for citing facts attributed to a source
  not actually present in the scraped material -- expect genuine rejections, not just approvals, on a full run.

## Deviations from the design

- Auth routes are `POST /auth/signup`, `/login` and `/logout`; the design's `/auth/register`, `/auth/refresh` and OAuth
  routes do not exist. The app signs in through `supabase_flutter`, not these endpoints.
- The app reads articles straight from Supabase's REST and Storage APIs instead of proxying through the backend, which
  is what lets a physical phone work without the dev machine.
- Articles do not carry `is_liked`. The article screen's Like pill reads `LikeState` and `AuthState` itself, and
  `LikeState` loads a user's likes on sign-in, so neither has the design's `fetchUserLikes` or `likedArticleIds`.
- Suggestions come from a pre-computed `search_suggestions` table filled by a trigger, as the design says, but it holds
  titles and tags only: no person, event or period entities, which would need named-entity extraction (requirement 7.6's
  names that appear only in an article's text are found by search, not suggested). Its `frequency` column became
  `article_count`, and `SearchService.autocomplete` looks it up through the `autocomplete_suggestions` function.
- Suggestions replace the results while they show, rather than dropping down over them, and there is no arrow-key
  navigation: the rows are focusable and take Enter, so Tab reaches them.
- Offline storage is `shared_preferences` rather than sqflite, which has no web support, and eviction is by capacity, so
  there is no `clearOldCache`.
- `ContentValidator.validate` returns `(valid, issues)`, not a `ValidationResult`.
- The `users` table has no `password_hash` or OAuth columns: Supabase Auth owns them.
- The redesign's onboarding feature slides use their own bundled photos (`bharatverse_app/assets/onboarding/`, one
  per slide, sourced from Wikimedia Commons under CC BY-SA 4.0 / GODL-India) rather than the design handoff's own
  stock art or a live fetch from published articles (tried first, then replaced: onboarding runs before the reader
  has any articles to draw a photo from, and the design's own placeholder photos were judged not exciting enough).

## Not built

- robots.txt is not checked before scraping: `WebScraper.check_robots_txt` exists, but `respect_robots` is accepted and
  ignored.
- Alerting on critical errors (requirement 11.5) beyond a failed Actions run when nothing was published, and a rate
  limit shared across backend workers (it would need something like Redis).
- Native deep links for password reset: a phone app has to register a link scheme first. On the web, the link must be
  opened in the browser that asked for it (PKCE keeps the verifier there), and reloading while the new-password form is
  up leaves the reader signed in without one.
- `SearchFilters`; search while offline (nothing to search but the 50 cached articles' titles, tags and summaries --
  an offline `search_articles` would need its own copy of that logic).
- A share button on the article screen: the redesign's mockup has one, but there is no share package dependency yet
  and no defined per-article URL to share (the app has no deep-linkable article routes).
- The Settings sheet's notification toggles (`SettingsState.notifDaily`/`notifWeekly`/`notifAnnounce`) are UI +
  `SharedPreferences` only: no FCM/APNs integration, no backend table, and no code path that ever sends a
  notification. Toggling one can never mean a notification actually arrives -- push is out of scope for the
  product (`docs/requirements.md`), and neither design file for this redesign mentions it.
- The Settings sheet's "Download for offline" toggle (`SettingsState.offlineOn`) persists but is not wired to
  `ArticleCache`: every article opened is already cached regardless of this toggle's value, and turning it off does
  not stop that. Wiring it to real behavior (e.g. always keeping today's article cached even if it would otherwise
  be evicted) was judged more invasive than Milestone 1's scope warrants.

## Decisions

1. Build the vertical slice before broadening any layer.
2. Authentication is Supabase Auth, with no custom JWT code.
3. A physical iPhone was verified from a Mac with Xcode's free Personal Team signing. A debug build only launches from
   Xcode, because iOS grants the JIT permission it needs to a process with a debugger attached; use `--release` for an
   app that keeps working from the home screen. From Linux there is no native route (Xcode is Mac-only), so
   `scripts/run-device.sh` serves the web app to the phone's browser, where it installs from Safari's Add to Home
   Screen; that path has not been tried on an iPhone yet.
