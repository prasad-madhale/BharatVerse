# Local Supabase stand-in

Runs the parts of Supabase that BharatVerse uses on your own machine, so the app, API and content pipeline can be tried
and tested without a hosted project, and `schema.sql` can be exercised against a real database:

| Piece | What it is | Port |
|---|---|---|
| Postgres 17 | the database, with `schema.sql` applied | 54322 |
| PostgREST 16 | the REST API the app and backend call, verifying the same JWTs | 54323 |
| `gateway.py` | one URL in front of it (54321): `/rest/v1` proxied to PostgREST, a minimal GoTrue-style `/auth/v1` (email and password, refresh, password reset with PKCE) and a directory-backed `/storage/v1` | 54321 |
| backend API | this repo's FastAPI service, pointed at the gateway | 8000 |
| web app | the Flutter app built against the gateway | 8765 |

It is for testing, not a replacement for Supabase: there is no OAuth, email confirmation, storage policy or realtime,
Postgres trusts every local connection, and the JWT secret is the public Supabase development one. Everything listens on
127.0.0.1 only. Password-reset "emails" are collected at `GET /_mailbox` on the gateway.

## Set up

Needs Linux x86-64 (elsewhere, see below), `curl`, `tar` with xz, Python 3.12 and, for the web app, Flutter.

```bash
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r backend/requirements.txt -r tools/local-stack/requirements.txt
./tools/local-stack/stack.sh setup
```

`setup` downloads Postgres and PostgREST into `.local-stack/bin` (about 80 MB, each checked against a checksum pinned in
`fetch.sh`), creates the database in `.local-stack/0`, applies `bootstrap.sql` (the roles and `auth` schema Supabase
provides) and `backend/database/schema.sql`, starts everything, seeds three sample articles through the backend's own
`ArticleService`, and builds the web app if Flutter is on your `PATH`. Then open http://127.0.0.1:8765.

| Command | What it does |
|---|---|
| `stack.sh start`, `stop`, `status` | run, stop or list the services; data survives a stop |
| `stack.sh build` | rebuild the web app after changing Dart code |
| `stack.sh seed` | add the sample articles again (safe to repeat) |
| `stack.sh reset` | throw the data away and set up again |
| `stack.sh sql FILE` | run a SQL file, for example a schema change, and reload PostgREST's schema |
| `stack.sh env` | print `export SUPABASE_URL=...` lines for the backend and the pipeline |

The web app is built with `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`, which `lib/config.dart`
reads, so no source is edited. To publish an article into the stand-in run `eval "$(./tools/local-stack/stack.sh env)"`
and then the pipeline; the explicit variables keep it away from your hosted project.

## Test against it

The backend's integration tests read `../.env` and insert temporary rows. To run them here without touching a real
`.env`, point `BV_ENV_FILE` at the file `setup` wrote:

```bash
cd backend
BV_ENV_FILE="$PWD/../.local-stack/0/env" pytest -m integration --no-cov
```

The stand-in's own logic (the SQL splitter and the gateway's tokens and passwords) has tests that need no database, and
the search suggestions in `schema.sql` have a property test against a Python model, and the migration for an older
project has one that runs it twice and compares with a new project. These need the stack's Postgres running
(`stack.sh start`) and are skipped without it: each makes and drops databases of its own, and `BV_PROP_EXAMPLES` sets
how many random cases the property test tries. Run them with `python -m pytest tools/local-stack/tests`, adding
`BV_STACK_OFFSET` if the stack is not on the default ports, or `BV_TEST_LOCALE=en_US.utf8` to build their databases with
Supabase's collation instead of the stand-in's `C.UTF-8`. CI does not run them.

## A second stack

`BV_STACK_OFFSET=1000 ./tools/local-stack/stack.sh setup` shifts every port by 1000 (gateway 55321, Postgres 55322,
PostgREST 55323, API 9000, web 9765) and keeps its data in `.local-stack/1000`, so a stack for a branch under test can run
beside your own. The binaries are shared.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `BV_STACK_OFFSET` | `0` | added to every port |
| `BV_STACK_DIR` | `.local-stack/<offset>` | this stack's data, logs, keys and built web app |
| `BV_BIN_DIR` | `.local-stack/bin` | where `fetch.sh` puts the binaries |
| `BV_PG_BIN`, `BV_POSTGREST` | from `BV_BIN_DIR` | use your own Postgres 17 (`initdb`, `pg_ctl`, `postgres`) and PostgREST |
| `BV_PYTHON` | `python3` | the interpreter that has the requirements installed |
| `BV_JWT_SECRET` | the Supabase development secret | signs and verifies the local tokens |

## On another machine

Everything that gets installed is listed here. `requirements.txt` holds the Python packages (`pg8000` for SQL, because
the bundled Postgres has no `psql`, and `python-multipart` for the storage uploads). The binaries are Postgres
17.11 from the [zonky embedded-postgres-binaries](https://github.com/zonkyio/embedded-postgres-binaries) build on Maven
Central and PostgREST v16.3 from its GitHub releases, both pinned in `fetch.sh`. On macOS or arm64 Linux there is no
download: install Postgres 17 and PostgREST yourself (Homebrew has both) and run
`BV_PG_BIN=<dir with initdb> BV_POSTGREST=<postgrest> ./tools/local-stack/stack.sh setup`. That route has not been
tried here. To uninstall, run `stack.sh stop` and delete `.local-stack/`.
