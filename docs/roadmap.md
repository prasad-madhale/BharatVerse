# Roadmap

Status and sequencing. [`design.md`](design.md) is the architectural reference and [`requirements.md`](requirements.md)
the requirements; this file records what is built, where it differs from the design, and what is left. Status as of
2026-09-20.

## Phases

| Phase | Scope | Status |
|---|---|---|
| 0 | Vertical slice: scrape, generate, store, serve, display | Done, verified live |
| 1 | Auth: Supabase email and password, password reset | Done, verified live; OAuth not started |
| 2 | Search: full-text, then autocomplete, then semantic | Full-text done; autocomplete is next; semantic undecided |
| 3 | Likes and offline reading | Done |
| 4 | Validator, scheduler and daily automation | Done, verified live; the cron is off on purpose |
| 5 | Remaining mobile screens and polish | Done except a profile screen |
| 6 | Deployment | Not started |

"Verified live" means run against the real project and a real browser; the later features were verified against a local
Postgres and PostgREST running `schema.sql`, with the hosted project unchecked.

## What is built

- **Pipeline** (`scrapper/`): an LLM proposes topics that are not yet published; Wikipedia, archive.org and New World
  Encyclopedia are scraped; an LLM writes the article; automated checks (length, sections, citations) accept it; the
  service-role client publishes it. A generation failure retries with backoff, and one bad topic never stops the batch.
  The daily GitHub Actions workflow runs on demand only: its schedule stays commented out until the output is trusted
  over more unattended runs, so do not enable it without deciding that first. The daily workflow uses Claude Sonnet 5;
  a local run defaults to Gemini. Groq's free tier was tried and rejected for weak adherence to the word-count target.
- **API** (`backend/`): articles (`daily`, by id, paged list), full-text search, sign-up, login and logout, likes,
  rate limiting and JSON request logs.
- **App** (`bharatverse_app/`): home with recent articles, article, archive, search with highlighted terms, likes,
  sign-in and password reset, offline reading of the 50 most recently opened articles. It reads Supabase directly, so it
  works on a real phone without a local server. The design system is "Vintage Broadsheet" (parchment, saffron and India
  green; Newsreader and Work Sans) in `lib/theme/` and `lib/widgets/`.
- **Search**: `search_articles` in `schema.sql` ranks a weighted `search_vector` over title, tags and summary (not
  article bodies, which live in Storage), so a tag-only match is found too. PostgREST's `text_search` takes a column
  name, not an expression, which is why the vector is a stored column with a GIN index.

## Next

1. **Autocomplete** (Phase 2): `GET /articles/search/autocomplete?q=` and `ApiClient.getAutocompleteSuggestions`, as in
   the design. The `search_suggestions` table exists but nothing fills it.
2. **Semantic search**: the placeholder `article_embeddings` table was removed. It needs pgvector and an embeddings
   provider, and is worth deferring past the rest of the MVP.
3. **Deployment** (Phase 6): a backend Dockerfile, a hosting choice, the scheduler on that host, and app store
   preparation (icons, signing, review lead time, especially on iOS).

## Needs a person

- **Hosted Supabase project.** Apply changes to `schema.sql` by hand. As last checked it lacked the `search_vector`
  column and the `search_articles` function, so search fails there until they are applied (drop an older
  `search_vector` first). Supabase permanently deactivates free projects paused for over 90 days, which is how the first
  project was lost: restore a paused one promptly. Add the app's URL under Authentication > URL Configuration >
  Redirect URLs for password reset, and keep email confirmation off, or sign-up returns no session.
- **OAuth.** Google and Facebook app registration has days of review lead time and has not been started.
- **Hosting**, the daily cron, and app store accounts.

## Deviations from the design

- Auth routes are `POST /auth/signup`, `/login` and `/logout`; the design's `/auth/register`, `/auth/refresh` and OAuth
  routes do not exist. The app signs in through `supabase_flutter`, not these endpoints.
- The app reads articles straight from Supabase's REST and Storage APIs instead of proxying through the backend, which
  is what lets a physical phone work without the dev machine.
- Articles do not carry `is_liked`. `LikeButton` reads `LikeState` and `AuthState` itself, and `LikeState` loads a user's
  likes on sign-in, so neither has the design's `fetchUserLikes` or `likedArticleIds`. Likes open from a header icon,
  as there is no `ProfileScreen`.
- Offline storage is `shared_preferences` rather than sqflite, which has no web support, and eviction is by capacity, so
  there is no `clearOldCache`.
- `ContentValidator.validate` returns `(valid, issues)`, not a `ValidationResult`.
- The `users` table has no `password_hash` or OAuth columns: Supabase Auth owns them.

## Not built

- robots.txt is not checked before scraping: `WebScraper.check_robots_txt` exists, but `respect_robots` is accepted and
  ignored.
- Alerting on critical errors (requirement 11.5) beyond a failed Actions run when nothing was published, and a rate
  limit shared across backend workers (it would need something like Redis).
- Native deep links for password reset: a phone app has to register a link scheme first. On the web, the link must be
  opened in the browser that asked for it (PKCE keeps the verifier there), and reloading while the new-password form is
  up leaves the reader signed in without one.
- Branded native launcher icons: the web icons are a placeholder monogram, and the Android and iOS ones are still
  Flutter's default.
- `SearchFilters`, highlighting of stemmed forms (searching "empires" finds "Empire" but does not mark it), and search or
  likes while offline.

## Decisions

1. Build the vertical slice before broadening any layer.
2. Authentication is Supabase Auth, with no custom JWT code.
3. A physical iPhone was verified from a Mac with Xcode's free Personal Team signing. A debug build only launches from
   Xcode, because iOS grants the JIT permission it needs to a process with a debugger attached; use `--release` for an
   app that keeps working from the home screen. From Linux there is no native route (Xcode is Mac-only), so
   `scripts/run-device.sh` serves the web app to the phone's browser, where it installs from Safari's Add to Home
   Screen; that path has not been tried on an iPhone yet.
