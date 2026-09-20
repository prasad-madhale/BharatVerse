# AGENTS.md

BharatVerse serves one AI-written story from Indian history a day. Monorepo: `scrapper/` (scrape, generate, validate), `backend/` (FastAPI over Supabase), `common/` (shared models and LLM provider), `bharatverse_app/` (Flutter). Build status: `.kiro/specs/bharatverse-mvp/roadmap.md`. Contract for endpoints, services and Flutter classes: `.kiro/specs/bharatverse-mvp/design.md`.

## Setup
- Python 3.12 with one venv at the repo root: `pip install -r backend/requirements.txt -r scrapper/requirements.txt`, then `playwright install --with-deps chromium`. Leave `fastapi==0.109.0` and `supabase==2.9.0` pinned; newer releases rename `gotrue` and change the missing-bearer status, which breaks tests.
- Flutter SDK per `bharatverse_app/pubspec.lock`.
- Secrets go in a root `.env` (template: `.env.example`), never committed. Tests need none.
- `./scripts/dev.sh` runs the backend (:8000) and the Flutter web app (:8765).

## Checks (what CI runs)
`./build.sh --check` runs all of them without editing files. Individually:
- `cd backend && pytest -m "not integration"`, and the same in `common/` and `scrapper/`. Each enforces 85% coverage.
- From the root: `autopep8 --recursive --aggressive --aggressive --max-line-length=127 --exit-code --diff backend/ scrapper/ common/` and `flake8 . --select=E9,F63,F7,F82 --exclude=.venv,.git,.agent,bharatverse_app,scripts`.
- In `bharatverse_app/`: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test --coverage`, then `../scripts/check_lcov_coverage.sh coverage/lcov.info 85 lib/main.dart`.
- Don't run `integration` tests, the scraper, or the daily pipeline unless asked: they need live credentials and cost money.

## Conventions
- Follow `design.md` for endpoint paths, service interfaces, and Flutter class and method names. Record any deviation in the roadmap under "Deviations from design.md".
- Backend services are classes with async methods that call `get_supabase()`. The service-role client bypasses RLS, so filter per-user queries by `user_id`.
- Query tests run the real service through `backend/tests/wire.py` and assert the HTTP request rather than a mock's calls.
- Flutter state classes are `ChangeNotifier`s with constructor-injected dependencies. Reuse `lib/theme/` tokens and the `App*` widgets.
- Keep code concise and modular: one-line docstrings, comments only for a non-obvious why.
- When a feature lands, update the roadmap and the package README. Add no other markdown files (`.kiro/steering/documentation-rules.md`).

## Commits and PRs
- One-line subject, conventional and unscoped (`feat:`, `fix:`, `docs:`, `chore:`, `style:`, `refactor:`), no body.
- Commit locally. Don't push or open a PR without the owner's review.

## Good to know
- The daily cron in `.github/workflows/daily-pipeline.yml` is disabled on purpose. Leave it.
- Changes to `backend/database/schema.sql` must also be applied to the hosted Supabase project by hand.
- A local-model task queue lives in `.kiro/specs/bharatverse-mvp/agent-tasks/` (see its README; run it with `scripts/agent_loop.py`).
