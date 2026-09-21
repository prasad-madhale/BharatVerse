# Backend API

FastAPI service over Supabase. The mobile app reads articles, search and likes straight from Supabase, so this API is
not needed to run the app; it serves the same data, plus auth, over REST for other clients.

## Setup

Python 3.12. From the repo root, in a virtualenv: `pip install -r backend/requirements.txt`. Configuration comes from
a `.env` at the repo root (template: [`.env.example`](../.env.example)):

| Variable | Default | Meaning |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | required | your project's URL and keys (Settings > API) |
| `RATE_LIMIT_REQUESTS_PER_MINUTE` | `100` | per client address and worker process; `0` turns it off |
| `LOG_LEVEL` | `INFO` | `DEBUG`, `INFO`, `WARNING` or `ERROR` |
| `ARTICLES_STORAGE_BUCKET` | `articles` | Storage bucket that holds article content |
| `CORS_ORIGINS` | `["*"]` | JSON list of allowed origins |

The backend needs no LLM key. For a new Supabase project, run [`database/schema.sql`](database/schema.sql) in the SQL editor
(tables, row-level security, the weighted `search_vector` column, the `search_articles` function, and the suggestions
behind autocomplete) and create a public Storage bucket named `articles`.

A project made from an earlier schema must not re-run the whole file: the SQL editor runs it as one transaction, which
stops at the first policy or trigger that already exists. Run the file in [`database/migrations/`](database/migrations/)
that brings it up to date instead (`2026-09-search-and-autocomplete.sql` adds search and autocomplete; it can be run twice).
Every later schema change gets a migration file the same way, applied by hand. Until a project has this one, search fails
there, and so does the autocomplete endpoint, while the app simply shows no suggestions.

The suggestions live in `search_suggestions`, which a trigger rebuilds from `articles` after every insert, update or
delete, so publishing needs no extra step. A phrase is kept only if searching for it finds the article it came from, and a
rebuild that fails is reported as a warning and never stops an article being written. A rebuild scans every article (about
0.4 s at 2,000), which suits one article a day; make it incremental if writes ever become frequent. Only that trigger
writes the suggestions and only the service role writes `articles`: the public key has no write rights, so a request it
should not make fails at once instead of running the trigger. A restore or replication that switches triggers off leaves
the suggestions stale; run `SELECT rebuild_search_suggestions();` as `postgres` afterwards.

## Run

```bash
uvicorn backend.main:app --reload    # http://localhost:8000/docs
```

For production add `--host 0.0.0.0 --port 8000 --workers 4`. The rate limiter counts in memory, so each worker keeps its
own count; behind a proxy add `--proxy-headers --forwarded-allow-ips <proxy address>` so it counts the caller rather
than the proxy. There is no Dockerfile or hosting configuration yet (see the [roadmap](../docs/roadmap.md)).

## Endpoints

All under `/api/v1`, except `/health`.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/articles/daily` | today's article |
| `GET` | `/articles/{id}` | one article |
| `GET` | `/articles?limit=5&offset=0` | newest first; `limit` 1-20, `offset` pages through them |
| `GET` | `/articles/search?q=...&limit=20` | most relevant first over title, tags and summary; `limit` 1-50 |
| `GET` | `/articles/search/autocomplete?q=...&limit=10` | titles and tags that start with `q` (1-100 characters), the phrases more articles carry first; `limit` 1-20 |
| `POST` | `/auth/signup`, `/auth/login` | email and password |
| `POST` | `/auth/logout` | bearer token |
| `POST`, `DELETE` | `/articles/{id}/like` | like or unlike; bearer token |
| `GET` | `/users/me/likes` | the caller's liked articles; bearer token |
| `GET` | `/health` | liveness; exempt from rate limiting |

Not built: semantic search, OAuth and token refresh.

## Logs

Logs go to stdout as JSON lines at `LOG_LEVEL`. Every request logs its method, path (no query string), status, duration
and client address; a 4xx (including a 429 from the rate limiter) is a WARNING, and a 5xx or unhandled exception an
ERROR with its traceback:

```json
{"time": "2026-09-21T03:13:49.453+00:00", "level": "INFO", "logger": "backend.requests", "message": "GET /api/v1/articles 200", "method": "GET", "path": "/api/v1/articles", "status": 200, "duration_ms": 27.3, "client": "127.0.0.1"}
```

## Tests

```bash
cd backend && pytest -m "not integration"     # what CI runs; an 85% coverage gate is built in
```

Query tests run the real service through `tests/wire.py`, a stub HTTP transport, and assert the request that would be
sent rather than a mock's calls. Integration tests (`pytest -m integration`, in `tests/test_database/`) need a `.env`
with real Supabase keys (or `BV_ENV_FILE` pointing at another env file, such as the one
[`tools/local-stack`](../tools/local-stack/README.md) writes): they insert temporary rows into `articles` and delete them,
so run them against a project you own. CI skips them.

## Layout

- `api/`: routers, plus `middleware.py` (rate limiting and request logging)
- `services/`: business logic, async classes that call `get_supabase()`; the service-role client bypasses row-level
  security, so per-user queries filter on `user_id` themselves
- `models/`, `database/` (`schema.sql`, the Supabase client), `utils/` (the rate limiter)
- `config.py`, `main.py` (`create_app`)
