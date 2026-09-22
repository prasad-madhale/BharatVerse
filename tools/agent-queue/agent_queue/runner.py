"""Running one task end to end, and choosing which task is next."""

import json
import shutil
import subprocess
from pathlib import Path

from . import config
from .agent import run_agent
from .config import RunnerError
from .fidelity import fidelity_report
from .shell import base_env, tail
from .spec import Spec, apply_steps
from .worktree import (changed_paths, commit_task, discard_changes, done_ids, head_of, out_of_scope, prepare_worktree,
                       revert_entries, snapshot_patch)


# Task state lives outside the specs and outside git.

def state_file(task_id: str) -> Path:
    return config.ns.state_dir / f"{task_id}.json"


def load_state(task_id: str) -> dict:
    path = state_file(task_id)
    return json.loads(path.read_text()) if path.exists() else {}


def save_state(task_id: str, **fields) -> None:
    config.ns.state_dir.mkdir(parents=True, exist_ok=True)
    state_file(task_id).write_text(json.dumps(fields, indent=2))


def clear_state(task_id: str) -> None:
    state_file(task_id).unlink(missing_ok=True)


def unmet_requirements(spec: Spec) -> list:
    missing = []
    for req in spec.requires:
        if req.startswith("py:"):
            ok = subprocess.run(["python", "-c", f"import {req[3:]}"], env=base_env(), capture_output=True).returncode == 0
        else:
            ok = shutil.which(req, path=base_env()["PATH"]) is not None
        if not ok:
            missing.append(req)
    return missing


def run_verify(spec: Spec, wt: Path) -> tuple:
    """Run the spec's verify commands. (True, "") if all pass, else (False, the first failure's output)."""
    env = base_env(wt)
    for command in spec.verify:
        try:
            result = subprocess.run(["bash", "-c", command], cwd=wt, env=env, capture_output=True,
                                    text=True, timeout=config.VERIFY_TIMEOUT)
        except subprocess.TimeoutExpired:
            return False, f"$ {command}\ntimed out after {config.VERIFY_TIMEOUT // 60} minutes"
        if result.returncode != 0:
            return False, f"$ {command}\n(exit {result.returncode})\n{tail(result.stdout + chr(10) + result.stderr)}"
    return True, ""


def commit_verified(spec: Spec, wt: Path) -> None:
    sha = commit_task(spec, wt)
    clear_state(spec.id)
    print(f"[{spec.id}] committed {sha[:7]}", flush=True)


def attempt_task(spec: Spec, wt: Path, executor: str, attempt: int, notes: str) -> tuple:
    """One attempt. Returns (verified, feedback for the next attempt)."""
    head = head_of(wt)
    if executor == "reference":
        apply_steps(spec, wt, base_env(wt))
        claim = "DONE"
    else:
        claim = run_agent(spec, wt, notes, attempt)
    if head_of(wt) != head:
        raise RunnerError(f"{spec.id}: the agent moved HEAD. Inspect {wt} by hand; nothing was reverted.")

    entries = changed_paths(wt)
    bad = out_of_scope(entries, spec.allowed)
    if bad:
        revert_entries(wt, bad)
        print(f"[{spec.id}]   reverted out-of-scope changes: {[p for _, p in bad]}", flush=True)
        return False, ("You changed files that are not allowed; they were reverted: "
                       f"{[p for _, p in bad]}. Change only: {spec.allowed}.")
    if claim.startswith("BLOCKED"):
        print(f"[{spec.id}]   agent reported blocked: {claim}", flush=True)
        return False, f"You reported: {claim}"
    if not entries:
        print(f"[{spec.id}]   no changes made", flush=True)
        return False, "You made no changes. Follow the steps and change the allowed files."

    fidelity, tolerable = ("", True) if executor == "reference" else fidelity_report(spec, wt, entries)
    ok, failure = run_verify(spec, wt)
    # Blank lines and trailing spaces are cosmetic. If they are all that is left on the last attempt and the
    # checks pass, take the work rather than block a task over them.
    if ok and fidelity and tolerable and attempt == config.MAX_ATTEMPTS:
        print(f"[{spec.id}]   accepted with whitespace-only differences from the task text:\n{fidelity}", flush=True)
        fidelity = ""
    if ok and not fidelity:
        return True, ""
    parts = []
    if not ok:
        parts.append(f"Verification failed:\n{failure}")
        print(f"[{spec.id}]   verification failed:\n{failure}", flush=True)
    if fidelity:
        parts.append(fidelity)
        print(f"[{spec.id}]   does not match the task text:\n{fidelity}", flush=True)
    return False, "\n\n".join(parts)


def block_task(spec: Spec, wt: Path, reason: str) -> None:
    snapshot_patch(spec, wt, "failed")
    discard_changes(wt)
    save_state(spec.id, status="blocked", attempts=config.MAX_ATTEMPTS, reason=reason)
    saved = config.ns.log_dir / f"{spec.id}.failed.patch"
    print(f"[{spec.id}] BLOCKED after {config.MAX_ATTEMPTS} attempts; patch saved to {saved}", flush=True)


def run_task(spec: Spec, wt: Path, executor: str, review: bool, feedback: str = "") -> bool:
    """Execute one task. True if it ended verified (committed, or pending review)."""
    prepare_worktree(spec, wt)
    resuming = load_state(spec.id).get("status") == "pending"
    if not resuming and changed_paths(wt):
        raise RunnerError(f"worktree {wt} has uncommitted changes; resolve them before starting {spec.id}")
    if resuming:
        kept = snapshot_patch(spec, wt, "pending")
        print(f"[{spec.id}] verified work saved to {kept} before applying feedback", flush=True)

    notes = feedback
    for attempt in range(1, config.MAX_ATTEMPTS + 1):
        print(f"[{spec.id}] attempt {attempt}/{config.MAX_ATTEMPTS} ({executor})", flush=True)
        verified, notes = attempt_task(spec, wt, executor, attempt, notes)
        if not verified:
            continue
        if review:
            save_state(spec.id, status="pending", attempts=attempt)
            print(f"[{spec.id}] verified, waiting for review. `agent_loop.py commit {spec.id}` to accept.", flush=True)
        else:
            commit_verified(spec, wt)
        return True
    block_task(spec, wt, notes)
    return False


def next_task(specs: list):
    """The next runnable spec, or a (None, reason) pair explaining why nothing is."""
    done = done_ids()
    for spec in specs:
        if spec.id in done:
            continue
        status = load_state(spec.id).get("status")
        if status == "pending":
            return None, f"{spec.id} is verified and waiting for review (commit or discard it)"
        if status == "blocked":
            continue
        if any(dep not in done for dep in spec.depends_on):
            continue
        missing = unmet_requirements(spec)
        if missing:
            print(f"[{spec.id}] skipped: missing requirement(s) {missing}", flush=True)
            continue
        return spec, ""
    return None, "queue empty (every task is done, blocked, or waiting on a dependency)"
