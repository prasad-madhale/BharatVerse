# Agent task queue

Self-contained implementation specs for a small local model (`qwen3.5:9b` through `claude-local`) to execute
unattended. Each `TASK-*.md` is one commit's worth of work: exact files, exact code, and a `verify:` list of
commands that must exit 0. A stronger model wrote them from a direct read of the code, so the executing model
designs nothing. If a spec does not say what to do, that is a bug in the spec, not an invitation to improvise.

## Running it

`scripts/agent_loop.py` runs the queue (the code is the `scripts/agent_queue/` package). It does its work on one
branch, `agent/queue`, in its own git worktree under `.agent/`, so your checkout is never touched. It never pushes.

TASK-001 fixes code that exists only on the unmerged branch `claude/project-status-n4reoq`. Until that branch
is merged, start the queue from it with `--base origin/claude/project-status-n4reoq` instead of `--base main`.

```bash
scripts/agent_loop.py list                      # tasks and their state
scripts/agent_loop.py run --base main --review  # run one task, stop, leave it uncommitted for you to inspect
scripts/agent_loop.py commit TASK-001           # accept it (re-verifies first)
scripts/agent_loop.py run --base main           # or: run the whole queue unattended, one commit per task
scripts/agent_loop.py run --watch 300           # keep watching for new tasks; touch .agent/STOP to end
```

Other commands: `discard ID` drops pending work, `unblock ID` retries a blocked task, `verify ID` runs a task's
checks against the worktree, `run --dry-run` prints the prompt the agent would get, and
`run --task ID --review --feedback "..."` sends a reviewer's comments back to the agent for another pass.
`run --executor reference` applies each spec's steps mechanically with no model. That proves a spec is complete and
detects drift: if the codebase changes and a spec no longer applies, the reference run fails on it.

The runner has its own tests: `python -m pytest scripts/tests`. They use a throwaway repo, toy specs, and a stub
agent, so they need no model, network, or real specs.

## What the runner enforces, independent of the model

- Only files listed under `allowed` may change. Anything else is reverted and the attempt is failed.
- The agent may not move `HEAD`. If it does, the runner stops and asks for a human.
- The runner runs the `verify:` commands itself. The agent's own claim of success is ignored.
- Three attempts per task. A task that still fails is reverted, its patch saved under `.agent/logs/`, and it is
  marked blocked. The rest of the queue continues, except tasks that depend on it.
- The agent runs in `dontAsk` mode with a small tool allowlist, with git credentials and the SSH agent removed
  from its environment. `git push`, `commit`, `checkout`, `reset`, `rm`, `curl`, and `pip` are denied.

## The contract the agent is held to

1. Follow the steps in order. Edit only the `allowed` files. Do not explore the repo.
2. Copy code exactly. Never invent an API call shape. If a step cannot be done as written, stop.
3. Run every `verify:` command and fix what fails. End with `DONE` or `BLOCKED: <reason>`.
4. Never run the scraper, `pytest` without `-m "not integration"`, or anything that touches live Supabase.
5. Never edit `.github/workflows/`, `schema.sql`, `config.dart`, dependency pins, or `.env`.

## Step markers

Each step is an HTML comment followed by fenced code, so the same spec serves a model and a mechanical executor:

| Marker | Meaning |
|---|---|
| `<!-- step: create PATH -->` | write PATH with exactly the next fenced block |
| `<!-- step: replace PATH -->` | in PATH, replace the first fenced block with the second, exactly |
| `<!-- step: run -->` | run the next fenced block with bash from the repo root |

## Front matter

`id`, `title`, `depends_on` (comma list), `requires` (commands, or `py:module` for an importable package; the task
is skipped when one is missing), `allowed` (comma list of paths or globs), repeated `verify:` lines, and `commit`
(the subject line). The runner adds a `Task: ID` trailer, which is how it knows a task is done.

Keep backticks out of `verify:` lines. The agent's permission system treats them as command substitution and denies
the command, and the model then burns turns working around it. A `.` in a grep pattern matches a backtick.

## Task list

| Task | What | Depends on |
|---|---|---|
| TASK-001 | Fix full-text search: wrong option name and invalid call order, plus a wire-level test helper | none |
| TASK-002 | Break daily-article ties on `created_at` | 001 |
| TASK-003 | Fix Wikipedia search: unpack the suggestion tuple, drop duplicate pages | none |
| TASK-004 | `LikeService` per `design.md`: like, unlike, `is_liked`, `get_user_likes`, `get_article_like_count` | 001 |
| TASK-005 | Likes endpoints at the design paths (`POST`/`DELETE /articles/{id}/like`, `GET /users/me/likes`) | 004 |
| TASK-006 | README project status | 005 |
| TASK-007 | `AGENTS.md` status | 001, 005 |
| TASK-008 | `.env.example` model defaults and the roadmap's provider claim | none |
| TASK-009 | Stop sign-in and sign-up leaking a user's session into the shared Supabase client | none |
| TASK-010 | Serve search at `/articles/search`, registered before the articles router | 005 |
| TASK-011 | Roadmap update: search, likes, fixes, and deviations from `design.md` | 010 |
| TASK-012 | Backend README status and endpoint list | 010 |
| TASK-013 | Flutter: `LikesClient` and `AuthState.accessToken` | none |
| TASK-014 | Flutter: `LikeState` | 013 |
| TASK-015 | Flutter: `LikeButton` in the article screen header, provided in `main.dart` | 014 |

All fifteen have been executed by `qwen3.5:9b` on `agent/queue`, one commit each. The specs record what the model
was told to write. Follow-up commits on that branch then trimmed comments, moved duplicated test helpers into shared
files, and renamed `LikeState.toggle` and `AuthState.accessToken` to the `design.md` names `toggleLike` and
`authToken`. Replaying the specs from scratch therefore reproduces the branch as it was before those commits.

## Conventions the specs assume

The code the specs write follows the packages' own patterns, so the diff reads like the rest of the repo.

- **API contract.** `design.md` section 2.5 is the source of truth for endpoint paths and service interfaces.
  Where the implementation departs from it (`/auth/signup`, search ordered by date, no `is_liked` on articles) the
  roadmap says so under "Deviations from design.md".
- **Python.** `autopep8` at 127 columns, enforced by CI, and `flake8` for syntax errors. Services are classes with
  async methods that call `get_supabase()`. Tests are `Test*` classes with a module docstring and descriptive names,
  no per-test docstrings, which is what every test written since July does.
- **Query tests.** A mocked Supabase client accepts any call chain, so tests that only check a mock passed against
  two real bugs here. Tests instead run the real service through a real postgrest builder and a stub HTTP transport
  (`backend/tests/wire.py`) and assert the request that would be sent, or fake a library with its real return
  contract. Each was checked by mutation: the tests fail when the fix is reverted.
- **Dart.** `dart format` and `flutter analyze` are enforced by CI. State classes extend `ChangeNotifier` and take
  their dependencies in the constructor, like `AuthState`. Services take an injectable `http.Client`, like
  `ApiClient`, and tests assert the requests through `MockClient`. Widgets reuse the design tokens in `lib/theme/`
  and the `App*` components in `lib/widgets/`.
- **Commits.** One-line conventional subjects with no scope and no body: `feat:`, `fix:`, `docs:`, `chore:`, `style:`, `refactor:`.
- **Docs.** Status lives in the roadmap and the package READMEs, updated as features land. No new markdown files
  outside `.kiro/specs/`.

## Work that needs a person

The agent must not attempt these. Each needs live credentials, money, an external party, or a product decision.

**Needs live Supabase access**

- Apply the `search_vector` migration. `backend/database/schema.sql` adds a generated column and a GIN index. They
  work on a local Postgres and PostgREST, but have not been run against the hosted project, which did not resolve on
  2026-09-20 (see the roadmap). Until they are, every search request there fails in Postgres. Then try a two-word
  query.
- Try likes end to end against the hosted project. Locally, with real user tokens, a like, an unlike, and a repeated
  like all behave. The app depends on the `likes` policies: select, insert, and delete exist, and there is no update
  policy, which is why it inserts with `ignore-duplicates` rather than merging.

**Costs money or writes to production**

- Running the daily pipeline. Each run makes real LLM calls and inserts a real article. It has never run on GitHub.
- Re-enabling the daily cron. The roadmap says not to without discussing first.

**Needs an external party**

- Google and Facebook OAuth registration, which takes days to review. App store preparation.

**Needs a product decision**

- Whether search should go through the backend. The app searches straight through PostgREST today, like likes and
  article reads, so no backend has to be deployed. Say so if that should change.
- Whether semantic search stays in the MVP, and the default LLM provider. `common/config.py` defaults to `gemini`
  and only the daily workflow picks `anthropic`.
- How autocomplete should work. The `search_suggestions` table has no unique index on `(term, category)`. A
  title-prefix query would need no schema change.

**Not the agent's job**

- Merging and pushing. The agent commits to `agent/queue` and stops. A person reviews the branch and pushes.
- `integration_test/app_screenshot_test.dart` is already stale: it builds screens without the providers they need
  and reads a manual fixture from `/tmp`. It is not run in CI.

## Environment

The verify commands need Python with the packages in `backend/requirements.txt` and `scrapper/requirements.txt`.
Install `supabase==2.9.0` and `fastapi==0.109.0` exactly: newer releases rename `gotrue` and change the status code
for a missing bearer header, which fails tests for reasons unrelated to the code. `crawl4ai` 0.4.24 does not build
on Python 3.14; use Python 3.12 (the repo's `.python-version`) or an unpinned crawl4ai. Point `BV_AGENT_VENV` at the
virtualenv, or create it at `.agent/venv`. Set `BV_GIT_NAME` and `BV_GIT_EMAIL` if git has no identity configured.

Flutter tasks need the Flutter SDK at `.agent/flutter` (the runner puts its `bin/` on the path) and a package cache
at `.agent/pub-cache`. `pubspec.lock` requires Flutter 3.38.4 or newer. On a different SDK, `flutter pub get`
rewrites four SDK-pinned test packages in `pubspec.lock`. The runner restores the file, and every command uses
`--no-pub` so it is not rewritten again.
