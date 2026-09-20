# AGENTS.md - BharatVerse Codebase Guide

This document provides essential information for AI agents working within the BharatVerse repository. It outlines project structure, commands, conventions, and important considerations to facilitate effective contributions.

> **Current implementation status**: the scrape, generate, validate, store, serve, and display pipeline works
> end to end (the roadmap records what has been verified live). `scrapper/` has `scrapper_main.py`, the daily
> scheduler, topic generation, and content validation. `backend/` has `main.py` with articles, auth, search, and
> likes routers. `bharatverse_app/` has Home, Article Detail, and Sign-in screens, plus a like button on the
> article screen. Search and likes are verified against a local Postgres and PostgREST, not yet the hosted Supabase
> project, and the app has no search or offline-cache screens yet. See
> [.kiro/specs/bharatverse-mvp/roadmap.md](specs/bharatverse-mvp/roadmap.md) for the current build order.

## Project Overview

The BharatVerse repository is a monorepo containing three primary services:
1.  **`bharatverse_app`**: A cross-platform mobile application developed using Flutter.
2.  **`backend`**: A FastAPI-based REST API server.
3.  **`scrapper`**: A Python-based content generation pipeline.

## `bharatverse_app` (Flutter Application)

### Overview
A Flutter app using Provider for state, Supabase for auth, and the Vintage Broadsheet design system. Screens: Home, Article Detail, Sign-in.

### Essential Commands

**Setup:**
To fetch project dependencies, navigate to the `bharatverse_app` directory and run:
```bash
flutter pub get
```

**Run the application:**
From the `bharatverse_app` directory:
```bash
flutter run
```

**Run tests:**
From the `bharatverse_app` directory:
```bash
flutter test
```

### Code Organization
The project follows a standard Flutter directory structure. Key directories include:
*   `lib/`: Contains the main application source code. `lib/main.dart` is the entry point.
*   `test/`: Contains unit and widget tests. Grouped as `test/models/`, `test/services/`, `test/screens/`, and `test/state/`.

### Naming Conventions and Style
The codebase adheres to standard Dart and Flutter naming conventions:
*   Classes and type names use `CamelCase` (e.g., `MyApp`, `MyHomePage`).
*   Private members are prefixed with an underscore (`_lowerCamelCase`) (e.g., `_MyHomePageState`, `_counter`).
*   Variables and functions use `lowerCamelCase`.

### Testing Approach
Widget testing is implemented using the `flutter_test` package. Tests are located in the `test/` directory.

## Testing

`backend/`, `scrapper/`, and `common/` each enforce a minimum of 85% source coverage on every `pytest`
run automatically (via that package's `pytest.ini` addopts + `.coveragerc` -- test files themselves are
excluded from the measurement). A run fails outright if coverage drops below that.

### Backend and Scrapper Tests
From the project root with virtual environment activated, run per-package (not from the repo root --
each package's `pytest.ini`/`.coveragerc` is relative to its own directory):
```bash
cd backend && pytest    # coverage report + 85% gate enforced automatically
cd scrapper && pytest -m "not integration"
cd common && pytest

# Run property-based tests only (backend)
pytest -m property_test
```

### Mobile Tests
From the `bharatverse_app` directory:
```bash
flutter test

# With coverage + 85% gate (main.dart excluded, it's pure bootstrapping)
flutter test --coverage
../scripts/check_lcov_coverage.sh coverage/lcov.info 85 "lib/main.dart"
```

### Whole-repo build/format/lint/test
`./build.sh` (repo root) installs dependencies, formats and lints everything, and runs every package's
test+coverage suite. `./build.sh --check` runs the same checks non-mutating (fails instead of
auto-fixing formatting) -- this is what CI and the pre-push hook run.

One-time setup to enable the pre-push hook: `git config core.hooksPath scripts/git-hooks`.

## `scrapper` (Python Content Pipeline)

### Overview
This project contains the content generation pipeline that scrapes historical content and uses LLM to generate curated articles.

### Essential Commands

**Setup:**
1.  **Create a virtual environment:** From the project root (`BharatVerse/`):
    ```bash
    python3.12 -m venv .venv
    source .venv/bin/activate  # On Windows: .venv\Scripts\activate
    ```
2.  **Install dependencies:** From the project root, ensure virtual environment is active:
    ```bash
    pip install -r scrapper/requirements.txt
    ```
3.  **Install browser binaries:** The scraper uses `playwright` for web scraping:
    ```bash
    playwright install
    ```

**Run the scraper:**
`scrapper/scrapper_main.py` runs the daily content pipeline: topic selection, multi-source scrape, LLM
generation, validation, and storage in Supabase. It makes real LLM calls and writes to the live database, so run
it deliberately, never from a test or an automated loop:
```bash
python scrapper/scrapper_main.py --count 1
```

### Environment Variables
The scraper requires an LLM API key. Create a `.env` file in the `BharatVerse/` root directory:
```
LLM_PROVIDER=gemini
GEMINI_API_KEY=your_api_key_here
```

Supported providers: `gemini` (FREE, default), `anthropic`, `openai`, `groq`

### Code Organization
*   `scrapper_main.py`: Pipeline entry point, a thin `--count N` CLI over `scrapper/scheduler.py`.
*   `scrapper/web_scraper.py`: `WebScraper` class (Crawl4AI-based) — implemented and tested.
*   `scrapper/sources/`: Pluggable content sources (`wikipedia.py`, `archive_org.py`, `new_world_encyclopedia.py`) via a `ContentSource` ABC.
*   `scrapper/models/`: Contains Pydantic models for data structures, e.g., `article.py` defines the `Article`,
    `Section`, `Citation`, and `ScrapedContent` models.

### Naming Conventions and Style
The Python code follows PEP 8 conventions:
*   Functions and variables use `snake_case`.
*   Classes use `CamelCase` (e.g., `Article`).

## `backend` (FastAPI REST API)

### Overview
FastAPI-based REST API that serves articles to the mobile app, handles authentication, search, and user likes.

### Essential Commands

**Setup:**
1.  **Activate virtual environment:** (same as scrapper)
    ```bash
    source .venv/bin/activate  # On Windows: .venv\Scripts\activate
    ```
2.  **Install dependencies:**
    ```bash
    pip install -r backend/requirements.txt
    ```
3.  **Set up the database:** create a Supabase project, run `backend/database/schema.sql` in the Supabase SQL
    Editor, and create a public Storage bucket named `articles`. There is no local `init_db.py` script — the
    database is entirely hosted on Supabase.

**Run the API server:**
Development mode with hot reload:
```bash
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```

Production mode:
```bash
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --workers 4
```

**API Documentation:**
When running, visit:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

### Environment Variables
Add to `.env` file in project root:
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_supabase_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_supabase_service_role_key
ARTICLES_STORAGE_BUCKET=articles
```

Authentication is handled entirely by Supabase Auth — no JWT secret is configured in this app. Google/Facebook
OAuth providers are enabled directly in the Supabase dashboard (Authentication > Providers), not via env vars.

### Code Organization
*   `main.py`: FastAPI application entry point.
*   `api/`: API routers and endpoints (articles, auth, search, likes).
*   `services/`: Business logic layer.
*   `models/`: Data models and Pydantic schemas.
*   `database/`: Database operations and queries (Supabase client wrapper, `schema.sql`).
*   `utils/`: Utility functions — currently just `llm_provider.py` (unified LLM interface across
    Gemini/Anthropic/OpenAI/Groq, used for both text generation and embeddings).
*   `config.py`: Configuration management.

### Naming Conventions and Style
Follows PEP 8 conventions:
*   Functions and variables use `snake_case`.
*   Classes use `CamelCase`.
*   Async functions preferred for I/O operations.

### Testing Approach
`backend/tests/` covers config, the Supabase client, the API routers (`test_api/`), the services
(`test_services/`), and property-based persistence tests in `test_database/` (Hypothesis, some marked
`@pytest.mark.integration` and requiring a live Supabase connection). Query-shape tests run the real service
through the real postgrest builder via `backend/tests/wire.py`, so a wrong operator or call order fails a test
instead of passing a mock.

## General Gotchas and Patterns

*   **Python Version:** This project requires Python 3.12+. Use `python3.12 -m venv .venv` when creating the virtual environment.
*   **Shared Virtual Environment:** Backend and scrapper share the same `.venv` at the project root.
*   **Virtual Environments:** Always activate the virtual environment before installing packages or running Python scripts.
*   **Environment Variables:** Sensitive information like API keys are loaded via `.env` files using `python-dotenv`. Ensure the `.env` file is set up correctly in the project root.
*   **Database:** All persistent storage is in Supabase (PostgreSQL + Storage) — there is no local database file. Article content is stored as JSON in the `articles` Supabase Storage bucket; only metadata lives in the `articles` Postgres table.
*   **Asynchronous Operations:** The Python backend uses `asyncio` for asynchronous operations.
*   **Web Interaction:** The scraper uses Crawl4AI (which uses Playwright internally) for content extraction, with pluggable sources for Wikipedia (`wikipedia` package) and archive.org (`internetarchive` package) — not `langchain_community`.
*   **Data Models:** Pydantic is used throughout for data validation and serialization.
*   **API Documentation:** When backend is running, interactive API docs are available at `/docs` and `/redoc` endpoints.
