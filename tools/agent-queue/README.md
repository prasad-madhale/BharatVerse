# Agent task queue

Runs small, self-contained specs with a local model (for example `qwen3.5:9b` behind a `claude-local` command), one
commit per task, on its own branch (`agent/queue`) and git worktree under `.agent/`, so your checkout is never touched.
The runner, not the model, checks each change and commits. Nothing is ever pushed.

## Use

Put one spec per task in `tools/agent-queue/tasks/` (format below), then:

```bash
python tools/agent-queue/agent_loop.py list                      # tasks and their state
python tools/agent-queue/agent_loop.py run --base main --review  # one task, left uncommitted for you to inspect
python tools/agent-queue/agent_loop.py commit TASK-001           # accept it (re-verifies first)
python tools/agent-queue/agent_loop.py run --base main           # or the whole queue, one commit per task
python tools/agent-queue/agent_loop.py run --watch 300           # keep watching for new tasks; touch .agent/STOP to end
```

Also: `discard ID`, `unblock ID`, `verify ID`, `run --dry-run` (print the agent's prompt) and
`run --task ID --review --feedback "..."` (send review comments back for another pass). `run --executor reference`
applies each spec's steps mechanically with no model, which proves a spec is complete and detects drift.

## What the runner enforces, whatever the model does

- Only files listed under `allowed` may change; anything else is reverted and the attempt fails.
- The agent may not move `HEAD`; if it does, the runner stops and asks for a human.
- The runner runs the `verify:` commands itself and ignores the agent's claim of success.
- Three attempts per task. A task that still fails is reverted, its patch saved under `.agent/logs/`, and marked
  blocked; the rest of the queue continues except tasks that depend on it.
- The agent runs in `dontAsk` mode with a small tool allowlist, without git credentials. `git push`, `commit`,
  `checkout`, `reset`, `rm`, `curl` and `pip` are denied.

## Writing a spec

A file named `TASK-*.md` with front matter: `id`, `title`, `depends_on` (comma list), `requires` (commands, or
`py:module`; the task is skipped when one is missing), `allowed` (comma list of paths or globs), one or more `verify:`
lines, and `commit` (the one-line subject; the runner adds a `Task: ID` trailer, which is how it knows the task is
done). Steps are an HTML comment followed by a fenced block, so one spec serves a model and the mechanical executor:

| Marker | Meaning |
|---|---|
| `<!-- step: create PATH -->` | write PATH with exactly the next fenced block |
| `<!-- step: replace PATH -->` | in PATH, replace the first fenced block with the second, exactly |
| `<!-- step: run -->` | run the next fenced block with bash from the repo root |

The model is told to copy code exactly, edit only `allowed` files, run every `verify:` command, and end with `DONE` or
`BLOCKED: <reason>`. Keep backticks out of `verify:` lines: the agent's permission system reads them as command
substitution and denies the command. Past specs (search, likes, and their fixes) are in git history under
`.kiro/specs/bharatverse-mvp/agent-tasks/`.

## Setup

- Python with the packages in `backend/requirements.txt` and `scrapper/requirements.txt` (a virtualenv at `.agent/venv`,
  or point `BV_AGENT_VENV` at one).
- Flutter tasks find the SDK at `$FLUTTER_ROOT`, else `~/flutter/flutter`, else `.agent/flutter`.
- Environment: `BV_AGENT_CMD` (agent command, default `claude-local`), `BV_AGENT_TIMEOUT` (seconds per attempt,
  default 2400), `BV_GIT_NAME`/`BV_GIT_EMAIL` (commit identity when git has none), `BV_COMMIT_TRAILERS` (extra trailer
  lines).

## Tests

`python -m pytest tools/agent-queue/tests` runs the runner's own tests against a throwaway repo, toy specs and a stub
agent, so they need no model, network or real specs. They are not part of CI.
