"""
Run the agent task queue (tools/agent-queue/tasks/) one task at a time, on the agent/queue branch in
its own worktree. The runner, not the agent, checks scope, runs each spec's verify commands, and commits. Nothing is
pushed. See the queue's README.md for the contract the agent is held to.

  agent_loop.py list
  agent_loop.py run [--once] [--review] [--task ID] [--base REF] [--executor agent|reference] [--watch N]
  agent_loop.py commit ID | discard ID | unblock ID | verify ID

Environment:
  BV_AGENT_CMD        agent command, default "claude-local"
  BV_AGENT_VENV       virtualenv whose bin/ goes first on PATH, default .agent/venv
  BV_AGENT_TIMEOUT    seconds one agent attempt may run, default 2400
  BV_GIT_NAME/EMAIL   commit identity, used only when git has none configured
  BV_COMMIT_TRAILERS  extra trailer lines appended to every commit message
"""

import argparse
import fcntl
import sys
import time
from pathlib import Path

from . import config
from .agent import build_prompt
from .config import RunnerError
from .runner import clear_state, commit_verified, load_state, next_task, run_task, run_verify
from .spec import load_specs
from .worktree import discard_changes, done_ids, ensure_worktree


def find(specs, task_id):
    for spec in specs:
        if spec.id == task_id:
            return spec
    raise RunnerError(f"unknown task {task_id}")


def cmd_list(args, specs):
    done = done_ids()
    for spec in specs:
        state = load_state(spec.id).get("status")
        if spec.id in done:
            label = "done"
        elif state:
            label = state
        elif any(dep not in done for dep in spec.depends_on):
            label = "waiting on " + ",".join(d for d in spec.depends_on if d not in done)
        else:
            label = "ready"
        print(f"{spec.id}  {label:<22} {spec.title}")


def cmd_run(args, specs):
    wt = Path(args.worktree).resolve()
    if args.dry_run:
        spec, reason = (find(specs, args.task), "") if args.task else next_task(specs)
        print(build_prompt(spec, args.feedback, wt) if spec else reason)
        return 0
    ensure_worktree(wt, args.base)
    last_reason = None
    while True:
        if config.STOP_FILE.exists():
            print("STOP file present; exiting.")
            return 0
        spec, reason = (find(specs, args.task), "") if args.task else next_task(specs)
        if spec is None:
            if reason != last_reason:  # a long --watch must not repeat itself in the log
                print(reason)
                last_reason = reason
            if args.watch and "waiting for review" not in reason:
                time.sleep(args.watch)
                specs = load_specs()
                continue
            return 0
        ok = run_task(spec, wt, args.executor, args.review, args.feedback)
        if args.once or args.task or (args.review and ok):
            return 0 if ok else 1


def cmd_commit(args, specs):
    spec = find(specs, args.id)
    wt = Path(args.worktree).resolve()
    if load_state(spec.id).get("status") != "pending":
        raise RunnerError(f"{spec.id} is not waiting for review")
    ok, failure = run_verify(spec, wt)
    if not ok:
        raise RunnerError(f"{spec.id} no longer verifies:\n{failure}")
    commit_verified(spec, wt)
    return 0


def cmd_discard(args, specs):
    spec = find(specs, args.id)
    discard_changes(Path(args.worktree).resolve())
    clear_state(spec.id)
    print(f"[{spec.id}] pending changes discarded")
    return 0


def cmd_unblock(args, specs):
    clear_state(find(specs, args.id).id)
    print(f"[{args.id}] unblocked")
    return 0


def cmd_verify(args, specs):
    ok, failure = run_verify(find(specs, args.id), Path(args.worktree).resolve())
    print("ok" if ok else failure)
    return 0 if ok else 1


COMMANDS = {"list": cmd_list, "run": cmd_run, "commit": cmd_commit, "discard": cmd_discard,
            "unblock": cmd_unblock, "verify": cmd_verify}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--namespace", default="queue", help="isolates branch, worktree, state and logs")
    parser.add_argument("--worktree", help="default: .agent/worktree (or worktree-NAMESPACE)")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("list")
    run = sub.add_parser("run")
    run.add_argument("--once", action="store_true", help="run at most one task")
    run.add_argument("--review", action="store_true", help="stop after each verified task, uncommitted")
    run.add_argument("--task", help="run this specific task id")
    run.add_argument("--base", default="main", help="ref the integration branch starts from (first run only)")
    run.add_argument("--executor", choices=["agent", "reference"], default="agent")
    run.add_argument("--feedback", default="", help="extra instructions appended to the agent's prompt")
    run.add_argument("--watch", type=int, default=0, help="when the queue is empty, rescan every N seconds")
    run.add_argument("--dry-run", action="store_true", help="print the prompt for the next task and exit")
    for name in ("commit", "discard", "unblock", "verify"):
        sub.add_parser(name).add_argument("id")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    args.command = args.command or "list"
    args.worktree = args.worktree or str(config.configure(args.namespace))

    config.AGENT_DIR.mkdir(exist_ok=True)
    lock = open(config.AGENT_DIR / "lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("another agent_loop.py is already running", file=sys.stderr)
        return 2
    try:
        return COMMANDS[args.command](args, load_specs()) or 0
    except RunnerError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
