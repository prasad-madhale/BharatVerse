# Agent task queue

Self-contained implementation specs for a small local model (`qwen3.5:9b` through `claude-local`) to execute
unattended. Each `TASK-*.md` is one commit's worth of work: exact files, exact code, and a `verify:` list of
commands that must exit 0. A stronger model wrote them from a direct read of the code, so the executing model
designs nothing. If a spec does not say what to do, that is a bug in the spec, not an invitation to improvise.

## Running it

`scripts/agent_loop.py` runs the queue. It does its work on one branch, `agent/queue`, in its own git worktree
under `.agent/`, so your checkout is never touched. It never pushes.

TASK-001 fixes code that exists only on the unmerged branch `claude/project-status-n4reoq`. Until that branch
is merged, start the queue from it with `--base origin/claude/project-status-n4reoq` instead of `--base main`.

```bash
# one-time: Python env for the verify commands (Python 3.12 is ideal; see "Environment" below)
scripts/agent_loop.py list                      # tasks and their state
scripts/agent_loop.py run --base main --review  # run one task, stop, leave it uncommitted for you to inspect
scripts/agent_loop.py commit TASK-001           # accept it (re-verifies first)
scripts/agent_loop.py run --base main           # or: run the whole queue unattended, one commit per task
scripts/agent_loop.py run --watch 300           # keep watching for new tasks; touch .agent/STOP to end
```

Other commands: `discard ID` drops pending work, `unblock ID` retries a blocked task, `verify ID` runs a task's
checks against the worktree, `run --dry-run` prints the prompt the agent would get. `run --executor reference`
applies each spec's steps mechanically with no model. That proves a spec is complete and detects drift: if the
codebase changes and a spec no longer applies, the reference run fails on it.

## What the runner enforces, independent of the model

- Only files listed under `allowed` may change. Anything else is reverted and the attempt is failed.
- The agent may not move `HEAD`. If it does, the runner stops and asks for a human.
- The runner runs the `verify:` commands itself. The agent's own claim of success is ignored.
- Two attempts per task. A task that still fails is reverted, its patch saved under `.agent/logs/`, and it is
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

## Task list

| Task | What | Depends on |
|---|---|---|
| TASK-001 | Fix full-text search: wrong option name and invalid call order, plus a wire-level test helper | none |
| TASK-002 | Break daily-article ties on `created_at` | 001 |
| TASK-003 | Fix Wikipedia search: unpack the suggestion tuple, drop duplicate pages | none |
| TASK-004 | `LikeService`, the data layer for likes | 001 |
| TASK-005 | Authenticated likes endpoints | 004 |
| TASK-006 | README project status | 005 |
| TASK-007 | `AGENTS.md` status | 001, 005 |
| TASK-008 | `.env.example` model defaults and the roadmap's provider claim | none |
| TASK-009 | Stop sign-in and sign-up leaking a user's session into the shared Supabase client | none |

Work that needs a person is in [HUMAN-GATED.md](HUMAN-GATED.md). The agent must skip it.

## Why the tests look the way they do

TASK-001 and TASK-003 fix defects that mock-based tests could not see. A mocked Supabase client accepts any call
chain and any option value, so a test that only checks the mock passes against broken code. Tests here run the
real service through a real postgrest query builder (`backend/tests/wire.py`) and assert the HTTP request that
would be sent, or fake the `wikipedia` library with its real return contract. Each was checked by mutation: the
tests fail when the fix is reverted.

## Environment

The verify commands need Python with the packages in `backend/requirements.txt` and `scrapper/requirements.txt`.
Install `supabase==2.9.0` and `fastapi==0.109.0` exactly: newer releases rename `gotrue` and change the status code
for a missing bearer header, which fails tests for reasons unrelated to the code. `crawl4ai` 0.4.24 does not build
on Python 3.14; use Python 3.12 (the repo's `.python-version`) or an unpinned crawl4ai. Point `BV_AGENT_VENV` at the
virtualenv, or create it at `.agent/venv`. Set `BV_GIT_NAME` and `BV_GIT_EMAIL` if git has no identity configured.
