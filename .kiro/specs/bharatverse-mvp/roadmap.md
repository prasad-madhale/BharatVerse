# BharatVerse MVP: Build Roadmap

## Status as of 2026-07-03

A direct code audit (not just a doc review) found this project earlier-stage than `requirements.md`/`design.md`/`tasks.md` suggest. No article has ever gone end-to-end: scrape → LLM-generate → validate → store → serve → display. This roadmap sequences the rebuild as a **vertical slice first**, then broadens phase by phase toward full MVP scope.

This doc governs *sequencing*. `tasks.md` remains the granular reference for property-test coverage (36 correctness properties) — each phase below cross-references the relevant `tasks.md` sections rather than duplicating them. `design.md` remains the architectural reference.

### What's actually real today
- **common/** (new): `llm_provider.py` + `config.py` (multi-provider LLM abstraction, shared settings) and `models.py` (`Article`/`Section`/`Citation`, shared by scrapper and backend) — extracted so the content pipeline doesn't depend on the backend service and the two don't drift on data shapes.
- **scrapper/**: `WebScraper`, `ArticleGenerator`, and `scrapper_main.py` — all real, tested, and verified end-to-end against the live Gemini API and real Wikipedia scrapes (~1900 words / 13 min reading time, deduplicated citations). Content validation, topic selection, and scheduling still don't exist (Phase 4).
- **backend/**: `config.py`, the Supabase client wrapper, `database/schema.sql`, `models/article.py` (`ArticleRecord`), `services/article_service.py`, `api/articles.py`, and `main.py` are all real. **Fully verified live end-to-end**: a fresh Supabase project (`jicmqxfqpbtjhwhuiohq`, replacing the dead one) has `schema.sql` applied and the `articles` Storage bucket created; `scrapper_main.py`'s output was saved via `ArticleService.save_article`, read back with matching content, and served over real HTTP via `GET /api/v1/articles/daily`. Auth, search, and likes still don't exist.
- **bharatverse_app/**: `lib/models/article.dart`, `lib/services/api_client.dart`, `lib/screens/home_screen.dart`, `lib/screens/article_detail_screen.dart` are real, replacing the counter-app template. `flutter analyze` clean, `flutter test` 10/10 passing (model parsing, `ApiClient` against mocked HTTP responses, widget tests for loading/error/retry/navigation). Not yet visually verified in a running browser/simulator. Auth/search/likes/offline-cache screens still don't exist (later phases).

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
- `backend/api/articles.py` — `GET /api/v1/articles/daily`, `GET /api/v1/articles/{id}`. Full CRUD/pagination/search is Phase 2.
- **New Supabase project**: `bvpwlzcertsoqetxpozn` (dead, permanently deactivated) replaced by `jicmqxfqpbtjhwhuiohq` ("BharatVerse-v2", same org, `us-west-2`), created via `supabase projects create`. `schema.sql` applied via `supabase db query --file ... --linked`; `articles` Storage bucket created (public, with an explicit `storage.objects` SELECT policy for the `articles` bucket -- needed because `ArticleService._load_article` downloads via the anon-key client, and the bucket's "public" flag alone doesn't bypass storage RLS for SDK downloads). `.env` updated directly (never pasted in chat). The project's Postgres password was generated locally and is not needed for the app itself (only for direct psql/CLI DB access, not used by `supabase-py`).

### Mobile — DONE (code + tests; not yet visually verified)
- `pubspec.yaml` — added `http` and `flutter_markdown_plus` (the original plan said `flutter_markdown`, but that package is discontinued -- replaced by the community fork); dropped unused `english_words`. `supabase_flutter` deferred to Phase 1 (auth) rather than added now unused.
- `lib/models/article.dart`, `lib/services/api_client.dart`, `lib/screens/home_screen.dart`, `lib/screens/article_detail_screen.dart` — replace the counter-app template in `main.dart`. `ApiClient` takes an injectable `http.Client` for testability.
- Tested against mocked HTTP responses (`package:http/testing.dart`), not a live backend, since the dev Supabase project is dead and the real API can't serve data yet -- consistent with the original "mock fixture data first" plan, just because the backend genuinely isn't reachable rather than by choice.
- **Still needed**: visual verification in a running browser/simulator (Chrome and macOS desktop targets are available locally via `flutter run -d chrome` / `-d macos`) once there's real data to point it at.

### Risks / open questions
- ~~`llm_provider.py`'s default `max_tokens` (2000) is likely too low~~ — raised to 4000 in `ArticleGenerator.generate_article`. Resolved.
- ~~First-pass strict-JSON parsing from the LLM will need prompt iteration~~ — confirmed in practice: the default Gemini model name was retired (`gemini-1.5-flash` → `gemini-2.5-flash`), and the initial word-count prompt was too weak (a live run produced 4121 words / 27 min against target; strengthened to a strict 1500-2000 word / 4-6 section instruction, now consistently within range). Resolved for gemini; anthropic/openai/groq default model names in `common/llm_provider.py` are unverified against live keys and may also be stale.
- ~~Confirm `crawl4ai==0.4.24` still installs cleanly~~ — confirmed, live scrapes work.
- New: Wikipedia search can return the same URL twice as separate scraped pages — citations are now deduplicated by `source_url` in `ArticleGenerator`, but the underlying duplicate-result behavior in `WikipediaSource` itself is still there and may be worth fixing at the source later.
- ~~The dev Supabase project is stuck-paused~~ — **resolved**. Diagnosed as permanent: status was `INACTIVE` (not `PAUSED`), project was ~140 days old, and Supabase permanently deactivates free-tier projects paused past 90 days (not reversible; support ticket SU-411542 was moot). No data was lost since Phase 0 never got past this project's pause. Replaced with a fresh project (`jicmqxfqpbtjhwhuiohq`) via the Supabase CLI -- schema applied, bucket created, `.env` updated, full pipeline (scrape → generate → save → serve over HTTP) verified live. See Backend section above for details.
- **Security note**: a `SUPABASE_ACCESS_TOKEN` was exposed in plaintext in a separate session while diagnosing the pause issue. Flagged immediately for revocation. All Supabase CLI operations for the new project setup used the CLI's own stored auth (already logged in) and freshly-generated values written directly to `.env` -- no tokens or passwords were pasted in chat during that work.
- **New, hard environment limitation**: there is no way to get a real, visually-representative screenshot of the Flutter app from this sandboxed dev environment. Headless `flutter test` widget tests use a fake software renderer with no real fonts (confirmed: text renders as illegible "tofu" boxes). `integration_test` (the correct mechanism for real-device rendering) doesn't support Chrome as a target yet, and macOS desktop builds fail because Xcode is incompletely installed (`xcrun: error: unable to find utility "xcodebuild"`) — confirmed via `flutter doctor`; no iOS Simulator or Android emulator are configured either. `integration_test/app_screenshot_test.dart` is committed as correct, ready-to-run infrastructure for the moment Xcode and/or Android Studio are installed. Until then, **the only way to actually see the app is to run `flutter run -d chrome` yourself** (this works today, no new installs needed) or install Xcode/Android Studio for simulator access.

### Testing pyramid (mobile)
Clarifying this since it came up: "simulator" isn't a stage after `flutter test` — a real simulator/emulator/browser run *is* how integration tests execute.
1. **Unit tests** (`test/models/`, `test/services/`) — pure Dart logic, headless Dart VM.
2. **Widget tests** (`test/screens/`) — renders the widget tree and checks structure/text/state transitions, still headless Dart VM with a fake renderer. Good for logic, **not** for visual review (this is what produced the illegible screenshot above).
3. **Integration tests** (`integration_test/app_screenshot_test.dart`) — real rendering on an actual simulator/emulator/browser/device via `flutter test integration_test/... -d <device>`. This is where real screenshots come from. Not runnable in this environment yet (see limitation above).
4. **Manual on-device testing** — a human actually using the app on a simulator or device.

### Exit criteria
One documented sequence takes a hardcoded topic through scrapper → Supabase → backend API → Flutter screen, showing real LLM-generated content on a simulator/device. **scrapper → Supabase → backend API is now fully proven live** (see Backend section above). The only remaining link is rendering on an actual simulator/device/browser -- still blocked by the no-simulator-available environment limitation above, needs either you running `flutter run -d chrome` yourself or Xcode/Android Studio installed.

**Reference**: `tasks.md` §4–9 cover the underlying scraper/generator/storage tasks in more granular (property-test-driven) form.

---

## Phase 1 — Auth (Supabase Auth, backend + mobile)

- `backend/services/auth_service.py` — thin wrapper over Supabase Auth calls (`sign_up`, `sign_in_with_password`, `sign_in_with_oauth`, `refresh_session`). No bcrypt/JWT issuance code.
- JWT-validation middleware dependency for protecting later endpoints (likes).
- Mobile: `Supabase.initialize(...)` + `lib/screens/auth_screen.dart` using the SDK's built-in sign-up/sign-in/OAuth — no custom token storage needed, the SDK handles session persistence.
- **Risk**: Google/Facebook OAuth app registration has real external review lead time (days). Start registration in parallel with Phase 0 work. Consider shipping email/password first, OAuth as a fast-follow within this phase.

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

## Phase 4 — Content Validator + Scheduler/Daily Automation

- `scrapper/scrapper/content_validator.py` — word count (≥1500), citations (≥1), structural checks, regenerate-on-failure loop.
- `scrapper/scrapper/scheduler.py` — replaces Phase 0's hardcoded-topic runner with real topic selection + uniqueness checking against existing articles.
- Populate a real `scrapper/data/web-sources.yaml` topic list (currently an empty placeholder).
- Wire daily automation (cron/hosted scheduler — exact mechanism depends on Phase 6 hosting choice).
- **Risk**: LLM cost/quality tuning is ongoing and easy to underestimate — budget real time here.

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
| 4 | Validator + scheduler | `content_validator.py`, `scheduler.py`, real `web-sources.yaml` | Hosting/cron choice, LLM cost |
| 5 | Remaining mobile screens | `search_screen.dart`, `profile_screen.dart` | Phase 2/3 APIs |
| 6 | Deployment | `Dockerfile`, hosting config | Hosting choice, app store review |
