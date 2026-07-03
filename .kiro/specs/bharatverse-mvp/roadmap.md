# BharatVerse MVP: Build Roadmap

## Status as of 2026-07-03

A direct code audit (not just a doc review) found this project earlier-stage than `requirements.md`/`design.md`/`tasks.md` suggest. No article has ever gone end-to-end: scrape → LLM-generate → validate → store → serve → display. This roadmap sequences the rebuild as a **vertical slice first**, then broadens phase by phase toward full MVP scope.

This doc governs *sequencing*. `tasks.md` remains the granular reference for property-test coverage (36 correctness properties) — each phase below cross-references the relevant `tasks.md` sections rather than duplicating them. `design.md` remains the architectural reference.

### What's actually real today
- **common/** (new): `llm_provider.py` + `config.py` (multi-provider LLM abstraction, shared settings) and `models.py` (`Article`/`Section`/`Citation`, shared by scrapper and backend) — extracted so the content pipeline doesn't depend on the backend service and the two don't drift on data shapes.
- **scrapper/**: `WebScraper`, `ArticleGenerator`, and `scrapper_main.py` — all real, tested, and verified end-to-end against the live Gemini API and real Wikipedia scrapes (~1900 words / 13 min reading time, deduplicated citations). Content validation, topic selection, and scheduling still don't exist (Phase 4).
- **backend/**: `config.py`, the Supabase client wrapper, `database/schema.sql`, `models/article.py` (`ArticleRecord`), `services/article_service.py`, `api/articles.py`, and `main.py` are all real. **The API now actually boots** (`uvicorn backend.main:app`) and serves `GET /api/v1/articles/daily`, `GET /api/v1/articles/{id}`, and `/health` — verified live with a running server. The Supabase Storage/Postgres calls inside `article_service.py` are unit-tested with a mocked client but **not yet verified against a live Supabase project** (the dev project is currently paused — see Risks below). Auth, search, and likes still don't exist.
- **bharatverse_app/**: default `flutter create` counter-app template. 0% feature work started — the next piece of Phase 0.

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

### Backend — CODE DONE, LIVE VERIFICATION PENDING
- `backend/main.py` — FastAPI entry point, wires config, CORS, `/health`, and the articles router. Verified live: booted the server, confirmed `/health` returns 200 and `/api/v1/articles/daily` correctly reaches the Supabase client before failing (paused project).
- `backend/models/article.py` — `ArticleRecord`, the metadata-only DB row shape (`common.models.Article` is used directly as the API response model — no separate response class needed).
- `backend/services/article_service.py` — `save_article`/`get_article_by_id`/`get_daily_article`, following the `content_file_path` + Supabase Storage pattern from `schema.sql`. Unit-tested with a mocked Supabase client; **not yet verified live**.
- `backend/api/articles.py` — `GET /api/v1/articles/daily`, `GET /api/v1/articles/{id}`. Full CRUD/pagination/search is Phase 2.
- **Blocked on**: the dev Supabase project is paused (DNS for the project host doesn't resolve while paused). Once resumed, still need to confirm `schema.sql` (including the updated `users` table) is applied and the `articles` Storage bucket exists, then re-run `scrapper_main.py` output through `ArticleService.save_article` and hit the live API to close the loop on Phase 0's exit criteria.

### Mobile
- `pubspec.yaml` — add `supabase_flutter`, `http`, `flutter_markdown`; drop unused `english_words`.
- `lib/models/article.dart`, `lib/services/api_client.dart`, `lib/screens/home_screen.dart`, `lib/screens/article_detail_screen.dart` — replace the counter-app template in `main.dart`.
- Build against mock fixture JSON first (matching `backend/models/article.py`'s shape), swap to the real API once backend Phase 0 work lands.

### Risks / open questions
- ~~`llm_provider.py`'s default `max_tokens` (2000) is likely too low~~ — raised to 4000 in `ArticleGenerator.generate_article`. Resolved.
- ~~First-pass strict-JSON parsing from the LLM will need prompt iteration~~ — confirmed in practice: the default Gemini model name was retired (`gemini-1.5-flash` → `gemini-2.5-flash`), and the initial word-count prompt was too weak (a live run produced 4121 words / 27 min against target; strengthened to a strict 1500-2000 word / 4-6 section instruction, now consistently within range). Resolved for gemini; anthropic/openai/groq default model names in `common/llm_provider.py` are unverified against live keys and may also be stale.
- ~~Confirm `crawl4ai==0.4.24` still installs cleanly~~ — confirmed, live scrapes work.
- New: Wikipedia search can return the same URL twice as separate scraped pages — citations are now deduplicated by `source_url` in `ArticleGenerator`, but the underlying duplicate-result behavior in `WikipediaSource` itself is still there and may be worth fixing at the source later.
- **Blocking**: the dev Supabase project (`bvpwlzcertsoqetxpozn.supabase.co`) is paused — DNS for it doesn't resolve. Needs to be resumed from the Supabase dashboard before `article_service.py`'s Storage/Postgres calls can be verified live, `schema.sql` re-confirmed as applied, and the `articles` Storage bucket confirmed to exist.

### Exit criteria
One documented sequence takes a hardcoded topic through scrapper → Supabase → backend API → Flutter screen, showing real LLM-generated content on a simulator/device.

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
