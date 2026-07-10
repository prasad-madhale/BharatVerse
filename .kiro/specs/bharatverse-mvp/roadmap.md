# BharatVerse MVP: Build Roadmap

## Status as of 2026-07-09

A direct code audit (not just a doc review) found this project earlier-stage than `requirements.md`/`design.md`/`tasks.md` suggest. No article had ever gone end-to-end: scrape → LLM-generate → validate → store → serve → display. This roadmap sequences the rebuild as a **vertical slice first**, then broadens phase by phase toward full MVP scope. That vertical slice, plus Phase 4 (pulled forward out of numeric order at explicit request), are now both done and verified live — see below.

This doc governs *sequencing*. `tasks.md` remains the granular reference for property-test coverage (36 correctness properties) — each phase below cross-references the relevant `tasks.md` sections rather than duplicating them. `design.md` remains the architectural reference.

### What's actually real today
- **common/**: `llm_provider.py` + `config.py` (multi-provider LLM abstraction, shared settings) and `models.py` (`Article`/`Section`/`Citation`, shared by scrapper and backend). Default provider is now **Claude Sonnet 5** (switched from Gemini after its free daily quota ran out mid-testing; Groq's free tier was tried and rejected — weaker instruction-following on word-count targets).
- **scrapper/**: `WebScraper`, `ArticleGenerator`, `TopicGenerator`, `ContentValidator`, `scheduler.py`, and three registered sources (`WikipediaSource`, `ArchiveOrgSource`, `NewWorldEncyclopediaSource`) — all real, tested, and verified end-to-end against live Claude Sonnet 5 + real multi-source scrapes. `scrapper_main.py` is now a thin `--count N` CLI wrapper around the scheduler, not a hardcoded topic. Ground rules (85% coverage gate, blocking format/lint) enforced on every commit.
- **backend/**: `config.py`, the Supabase client wrapper, `database/schema.sql`, `models/article.py` (`ArticleRecord`), `services/article_service.py` (`list_recent_titles` for topic dedup, `list_recent_articles` for the home screen), `api/articles.py` (`GET /articles` list + `/daily` + `/{id}`), and `main.py` are all real and verified live end-to-end. Auth, search, and likes still don't exist.
- **bharatverse_app/**: `lib/models/article.dart`, `lib/services/api_client.dart`, `lib/screens/home_screen.dart`, `lib/screens/article_detail_screen.dart` are real. Home screen now shows up to 5 recent articles (`ApiClient.getRecentArticles`), not just one. **Visually verified live**: `flutter run -d web-server` + Firefox renders real generated articles correctly end-to-end (home screen list → detail screen, tags, sections, citations all correct). Auth/search/likes/offline-cache screens still don't exist (later phases).
- **Local dev toolchain**: Xcode + CocoaPods + Android SDK (cmdline-tools, licenses) are now fully installed and verified via the new `scripts/doctor.sh` preflight check. Found and fixed a real bug getting the app onto a real iOS Simulator for the first time: `ApiClient` defaulted every non-web platform to the Android emulator's `10.0.2.2` alias, which doesn't resolve on iOS Simulator — now branches on `defaultTargetPlatform`. The iOS build itself succeeded after a DerivedData clear; a full on-screen visual confirmation on the simulator (vs. the already-proven web path) is still outstanding.
- **Daily automation**: `.github/workflows/daily-pipeline.yml` exists but its `schedule:` trigger is **intentionally commented out** (`workflow_dispatch` only) until output quality is trusted over more unattended runs — do not re-enable without discussing first. 5 real articles have now been generated and published across varied eras/themes (ancient metallurgy, Buddhist history, colonial-era battles, the independence movement), confirming the topic generator's dedup + variety instructions work in practice.

### Known gaps surfaced by live testing (not yet fixed, low priority)
- `ArticleService.get_daily_article()` just returns "most recent by `date`, limit 1" — if two articles share a date (e.g. manual testing, or a future >1/day scheduler run), which one shows is arbitrary/tie-broken by Postgres, not deliberate. Fine for real 1-article/day usage; will need real logic if that assumption ever changes.
- The home screen now shows up to 5 recent articles (was: only `get_daily_article()`'s single most-recent one), but there's still no full browse/search screen (Phase 2/5) — anything beyond the 5 most recent is reachable only via direct `GET /api/v1/articles/{id}`, not through the app UI.

### Standing architectural decisions (confirmed with product owner)
1. **Build order**: vertical slice first — one real article through the whole pipeline before broadening any layer.
2. **Auth**: Supabase Auth, not custom JWT. Drop `password_hash`/`oauth_provider`/`oauth_id` from the `users` table; rely on Supabase's built-in auth + `supabase_flutter` SDK.
3. **Mobile timing**: start in parallel, early — scaffold real screens against mock/fixture data as soon as the API contract shape is agreed, don't wait for the full backend.

---

## Phase 0 — Vertical Slice (do first, highest priority)

**Goal**: one real article — scraped → LLM-generated → stored in Supabase → served by the API → rendered on a Flutter screen. No search, auth, likes, scheduler, or rigorous validation yet.

### Scrapper — DONE
- `scrapper/scrapper/article_generator.py` — `ArticleGenerator`, using the new shared `common.llm_provider` (relocated from `backend/utils/` per the open design question — scrapper no longer depends on backend). Parses LLM output into the existing `scrapper/scrapper/models/article.py` Pydantic models; citations/reading-time/content assembly are derived from scraped data, not trusted from the LLM.
- `scrapper/scrapper_main.py` — minimal runner: hardcoded topic ("Mauryan Empire") → `WebScraper.search_and_scrape` → `ArticleGenerator.generate_article`. No validator, no scheduling yet.
- Verified end-to-end against the live Gemini API and real Wikipedia scrapes (1921 words / 13 min reading time, 5 sections, deduplicated citations).

### Backend — DONE, VERIFIED LIVE
- `backend/main.py` — FastAPI entry point, wires config, CORS, `/health`, and the articles router. Booted the server and confirmed `/health` (200) and `GET /api/v1/articles/daily` return a real article over real HTTP.
- `backend/models/article.py` — `ArticleRecord`, the metadata-only DB row shape (`common.models.Article` is used directly as the API response model — no separate response class needed).
- `backend/services/article_service.py` — `save_article`/`get_article_by_id`/`get_daily_article`, following the `content_file_path` + Supabase Storage pattern from `schema.sql`. Verified against the live project: saved a real generated article (Postgres row + Storage JSON blob), read it back via both the service directly and the anon-key client path, content and sections matched exactly.
- `backend/api/articles.py` — `GET /api/v1/articles/daily`, `GET /api/v1/articles/{id}`, and `GET /api/v1/articles` (list, `limit` query param default 5 max 20) added later to back the mobile home screen's multi-article view. Full CRUD/pagination/search is Phase 2.
- **New Supabase project**: `bvpwlzcertsoqetxpozn` (dead, permanently deactivated) replaced by `jicmqxfqpbtjhwhuiohq` ("BharatVerse-v2", same org, `us-west-2`), created via `supabase projects create`. `schema.sql` applied via `supabase db query --file ... --linked`; `articles` Storage bucket created (public, with an explicit `storage.objects` SELECT policy for the `articles` bucket -- needed because `ArticleService._load_article` downloads via the anon-key client, and the bucket's "public" flag alone doesn't bypass storage RLS for SDK downloads). `.env` updated directly (never pasted in chat). The project's Postgres password was generated locally and is not needed for the app itself (only for direct psql/CLI DB access, not used by `supabase-py`).

### Mobile — DONE, VERIFIED LIVE (web); iOS Simulator toolchain ready, on-screen confirmation still pending
- `pubspec.yaml` — added `http` and `flutter_markdown_plus` (the original plan said `flutter_markdown`, but that package is discontinued -- replaced by the community fork); dropped unused `english_words`. `supabase_flutter` added in Phase 1.
- `lib/models/article.dart`, `lib/services/api_client.dart`, `lib/screens/home_screen.dart` (now a multi-article list, see above), `lib/screens/article_detail_screen.dart` — replace the counter-app template in `main.dart`. `ApiClient` takes an injectable `http.Client` for testability.
- Visually verified live via `flutter run -d web-server` + Firefox against the real backend. iOS Simulator: toolchain fully set up and the build succeeds (see toolchain note above); full visual on-device confirmation not yet done in-session.

### Risks / open questions
- ~~`llm_provider.py`'s default `max_tokens` (2000) is likely too low~~ — raised to 4000 in `ArticleGenerator.generate_article`. Resolved.
- ~~First-pass strict-JSON parsing from the LLM will need prompt iteration~~ — confirmed in practice: the default Gemini model name was retired (`gemini-1.5-flash` → `gemini-2.5-flash`), and the initial word-count prompt was too weak (a live run produced 4121 words / 27 min against target; strengthened to a strict 1500-2000 word / 4-6 section instruction, now consistently within range). Resolved for gemini; anthropic/openai/groq default model names in `common/llm_provider.py` are unverified against live keys and may also be stale.
- ~~Confirm `crawl4ai==0.4.24` still installs cleanly~~ — confirmed, live scrapes work.
- New: Wikipedia search can return the same URL twice as separate scraped pages — citations are now deduplicated by `source_url` in `ArticleGenerator`, but the underlying duplicate-result behavior in `WikipediaSource` itself is still there and may be worth fixing at the source later.
- ~~The dev Supabase project is stuck-paused~~ — **resolved**. Diagnosed as permanent: status was `INACTIVE` (not `PAUSED`), project was ~140 days old, and Supabase permanently deactivates free-tier projects paused past 90 days (not reversible; support ticket SU-411542 was moot). No data was lost since Phase 0 never got past this project's pause. Replaced with a fresh project (`jicmqxfqpbtjhwhuiohq`) via the Supabase CLI -- schema applied, bucket created, `.env` updated, full pipeline (scrape → generate → save → serve over HTTP) verified live. See Backend section above for details.
- **Security note**: a `SUPABASE_ACCESS_TOKEN` was exposed in plaintext in a separate session while diagnosing the pause issue. Flagged immediately for revocation. All Supabase CLI operations for the new project setup used the CLI's own stored auth (already logged in) and freshly-generated values written directly to `.env` -- no tokens or passwords were pasted in chat during that work.
- ~~**Hard environment limitation**: no way to get a real, visually-representative screenshot~~ — **resolved**. `flutter run -d web-server` + a real Playwright-driven browser (not headless `flutter test`'s fake renderer) has been the proven path since Phase 0's exit criteria were met, and Xcode/CocoaPods/Android SDK are now all fully installed and verified via `scripts/doctor.sh`. `integration_test/app_screenshot_test.dart` (real-device rendering via `integration_test`) is still unexercised — the web-server + Playwright path has covered every visual-verification need so far instead.

### Testing pyramid (mobile)
Clarifying this since it came up: "simulator" isn't a stage after `flutter test` — a real simulator/emulator/browser run *is* how integration tests execute.
1. **Unit tests** (`test/models/`, `test/services/`) — pure Dart logic, headless Dart VM.
2. **Widget tests** (`test/screens/`) — renders the widget tree and checks structure/text/state transitions, still headless Dart VM with a fake renderer. Good for logic, **not** for visual review (this is what produced the illegible screenshot above).
3. **Integration tests** (`integration_test/app_screenshot_test.dart`) — real rendering on an actual simulator/emulator/browser/device via `flutter test integration_test/... -d <device>`. This is where real screenshots come from. Runnable now that toolchains are set up, but not yet actually run — Playwright against `web-server` has covered visual verification instead so far.
4. **Manual on-device testing** — a human actually using the app on a simulator or device.

### Exit criteria — MET
One documented sequence takes a hardcoded topic through scrapper → Supabase → backend API → Flutter screen, showing real LLM-generated content on a simulator/device. **Fully proven live end-to-end**, including the Flutter render: `flutter run -d web-server` + Firefox showed a real generated article correctly (home screen and detail screen, tags/sections/citations all correct). No Xcode/Android Studio/native simulator was needed — `web-server` is browser-agnostic and sidesteps that environment limitation entirely.

**Reference**: `tasks.md` §4–9 cover the underlying scraper/generator/storage tasks in more granular (property-test-driven) form.

---

## Phase 1 — Auth (Supabase Auth, backend + mobile) — DONE, VERIFIED LIVE

Email/password only; OAuth deferred as a fast-follow (real external review lead time, per the risk noted below — not yet started). Anonymous browsing is unchanged; auth is an optional path via an account icon, not a login wall.

- `backend/services/auth_service.py`, `backend/api/auth.py` (`/auth/signup`, `/login`, `/logout`) — thin wrappers over Supabase Auth, no bcrypt/JWT issuance code.
- `backend/api/deps.py`'s `get_current_user` — the JWT-validation dependency for protecting later endpoints (likes). Verifies via `client.auth.get_user(token)` (network round-trip, no new JWT dependency) rather than local signature verification. Not consumed by any endpoint yet — Phase 3 is the first real consumer.
- Mobile: `Supabase.initialize(...)` + `lib/state/auth_state.dart` + `lib/screens/auth_screen.dart`, using the SDK's built-in sign-up/sign-in directly (not proxied through our own `/auth/*` endpoints) so session persistence/refresh is handled automatically.
- Verified live end-to-end: signup, login (incl. wrong-password rejection), the existing `on_auth_user_created` trigger populating `public.users`, token verification (valid + garbage), logout, and the full flow through the real Flutter web UI.
- **Found via live testing**: the target Supabase project had email confirmation enabled, which silently prevented signup from returning a session (would have broken the mobile flow). Disabled via the dashboard after confirming with the user — a blind `supabase config push` was considered and rejected as too risky (would overwrite other live auth settings not visible locally).
- **Risk (unchanged, still applies to the OAuth fast-follow)**: Google/Facebook OAuth app registration has real external review lead time (days) — not yet started.

**Reference**: `tasks.md` §12.

---

## Phase 2 — Search (priority: FTS → autocomplete → semantic)

- `backend/services/search_service.py` + `backend/api/search.py`.
- The FTS index in `schema.sql` currently only covers `title`/`summary` (article content lives in Storage, not the DB row) — decide whether to denormalize a searchable text column.
- `search_suggestions` table exists but is never populated — needs an indexing hook on article save.
- `article_embeddings` currently stores embeddings as `TEXT`/JSON, not pgvector (schema.sql explicitly hedges on pgvector availability) — confirm pgvector is enabled on the target Supabase tier before committing to it.
- **Open question to resolve with product owner**: given semantic search's added complexity, consider deferring it past the rest of MVP scope (ship FTS + autocomplete first, semantic search as fast-follow).

**Reference**: `tasks.md` §10–11.

---

## Phase 3 — Likes + Offline Caching

- `backend/services/like_service.py` + `backend/api/likes.py` — schema/RLS already correct, no schema changes needed.
- Mobile `LikeButton`/`LikeState` (requires Phase 1 auth).
- `lib/services/article_cache.dart` (sqflite, last-7-days cache + LRU eviction) — independently buildable once Phase 0's `Article` model is stable; could be pulled earlier if mobile velocity allows.

**Reference**: `tasks.md` §13, §18.

---

## Phase 4 — Content Validator + Scheduler/Daily Automation — DONE, VERIFIED LIVE

Pulled forward out of numeric order at explicit request (done before Phases 1-3).

- `scrapper/scrapper/topic_generator.py` — `TopicGenerator` asks the LLM for fresh, Wikipedia-title-shaped topics, excluding titles already in Supabase (`ArticleService.list_recent_titles`).
- `scrapper/scrapper/content_validator.py` — word count (1500-2000, ±200 tolerance), ≥3 sections, ≥1 citation. Not a semantic/factual check (see gaps below).
- `scrapper/scrapper/scheduler.py` — `run_daily_pipeline(count)` replaces Phase 0's hardcoded-topic runner: topic selection → multi-source scrape → generate → validate → retry once (both generation errors and validation failures) → skip-and-continue on persistent failure, so one bad topic never aborts the rest of the batch.
- Three sources now registered and used: `WikipediaSource`, `ArchiveOrgSource` (existed, was never wired in), `NewWorldEncyclopediaSource` (new — no search API, guesses the direct `/entry/{Topic}` URL and relies on existing extract() failure-filtering if it 404s).
- `.github/workflows/daily-pipeline.yml` — daily cron exists but is **commented out** pending more confidence in output quality; `workflow_dispatch` works for manual runs.
- `scrapper/data/web-sources.yaml` deleted — it was an unused placeholder from before the plugin-based source registry existed; the Python registry (`scrapper/scrapper/sources/__init__.py`) is the real source of truth, no code ever read the yaml.
- **Real bugs found and fixed via live testing** (not caught by unit tests alone — see commit history `14fd71b`, `6214f01`, `07c60b1` for full detail): fair per-source character budget (one oversized source was silently crowding out others), Wikipedia's `#mw-content-text` CSS-selector scoping (crawl4ai was including thousands of characters of nav chrome before any real content), Claude's `ThinkingBlock` handling, symmetric word-count floor/ceiling prompt wording, `json-repair` for LLM JSON escaping mistakes, and the scheduler-crash-on-generation-error fix.
- **Residual risk, as predicted**: LLM cost/quality tuning took real, non-trivial time — five real bugs across ~10 live API calls before a genuinely good article came out reliably.

**Reference**: `tasks.md` §6–7.

---

## Phase 5 — Remaining Mobile Screens + Polish

- `lib/screens/search_screen.dart` (needs Phase 2), `lib/screens/profile_screen.dart` (needs Phase 3).
- Offline-aware UI states (cached-vs-live indicator, graceful degradation).
- `ArticleState`/`AuthState`/`LikeState` Provider `ChangeNotifier`s (per design.md) — implement per-screen as needed rather than upfront.

**Reference**: `tasks.md` §19–22.

---

## Phase 6 — Deployment

- Backend `Dockerfile` (referenced by both READMEs but doesn't exist yet).
- Hosting choice — not yet decided anywhere in the repo.
- Wire Phase 4's scheduler into the chosen host.
- Check what the existing root `build.sh` already automates (deps install, autopep8/flake8, pytest, Playwright/Chromium for Crawl4AI) before adding new deployment scripting on top of it.
- App store release prep (icons, signing, review lead time — especially iOS) — start early once feature-complete.

**Reference**: `tasks.md` §26.

---

## Summary Table

| Phase | Focus | Key new files | Hard external dependency |
|---|---|---|---|
| 0 | Vertical slice | `scrapper_main.py`, `article_generator.py`, `backend/main.py`, `api/articles.py`, `services/article_service.py`, `models/article.py`, mobile home/detail screens + `api_client.dart` | Live Supabase project + Storage bucket |
| 1 | Auth | `services/auth_service.py`, `api/auth.py`, `auth_screen.dart` | Google/Facebook OAuth app registration |
| 2 | Search | `services/search_service.py`, `api/search.py` | pgvector availability (semantic search) |
| 3 | Likes + offline | `services/like_service.py`, `api/likes.py`, `article_cache.dart` | none |
| 4 | Validator + scheduler | `content_validator.py`, `scheduler.py`, `topic_generator.py` | Hosting/cron choice, LLM cost |
| 5 | Remaining mobile screens | `search_screen.dart`, `profile_screen.dart` | Phase 2/3 APIs |
| 6 | Deployment | `Dockerfile`, hosting config | Hosting choice, app store review |
