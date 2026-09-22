"""The integration branch's git worktree: creating it, seeing what changed, committing, discarding."""

import fnmatch
import os
import re
import subprocess
from pathlib import Path

from . import config
from .config import RunnerError
from .shell import base_env, commit_env, git, tail
from .spec import Spec


def branch_exists() -> bool:
    ref = f"refs/heads/{config.ns.branch}"
    return git("rev-parse", "--verify", "--quiet", ref, cwd=config.REPO, check=False).returncode == 0


def ensure_worktree(wt: Path, base: str) -> None:
    if (wt / ".git").exists():
        return
    wt.parent.mkdir(parents=True, exist_ok=True)
    if branch_exists():
        git("worktree", "add", str(wt), config.ns.branch, cwd=config.REPO)
    else:
        git("worktree", "add", "-b", config.ns.branch, str(wt), base, cwd=config.REPO)


def changed_paths(wt: Path) -> list:
    """[(status, path)] for every tracked change and every untracked, non-ignored file."""
    out = git("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=wt).stdout
    entries, tokens, i = [], out.split("\0"), 0
    while i < len(tokens):
        token = tokens[i]
        if len(token) > 3:
            status, path = token[:2], token[3:]
            entries.append((status, path))
            if status[0] in "RC":  # rename/copy entries carry the origin path as the next token
                i += 1
        i += 1
    return entries


def out_of_scope(entries: list, allowed: list) -> list:
    return [(s, p) for s, p in entries if not any(fnmatch.fnmatch(p, pattern) for pattern in allowed)]


def revert_entries(wt: Path, entries: list) -> None:
    for status, path in entries:
        if status == "??":
            (wt / path).unlink(missing_ok=True)
        else:
            git("checkout", "HEAD", "--", path, cwd=wt)


def head_of(wt: Path) -> str:
    return git("rev-parse", "HEAD", cwd=wt).stdout.strip()


def done_ids() -> set:
    """Tasks already committed on the branch, read from their `Task:` trailers."""
    if not branch_exists():
        return set()
    log = git("log", config.ns.branch, "--format=%B", cwd=config.REPO).stdout
    return set(re.findall(r"(?m)^Task: (TASK-\d+)\s*$", log))


def snapshot_patch(spec: Spec, wt: Path, suffix: str) -> Path:
    """Write the worktree's uncommitted changes (untracked files included) to a patch file."""
    config.ns.log_dir.mkdir(parents=True, exist_ok=True)
    git("add", "-A", cwd=wt)
    patch = git("diff", "--cached", "HEAD", cwd=wt).stdout
    git("reset", "-q", cwd=wt)
    target = config.ns.log_dir / f"{spec.id}.{suffix}.patch"
    target.write_text(patch)
    return target


def discard_changes(wt: Path) -> None:
    git("reset", "-q", "--hard", "HEAD", cwd=wt)
    git("clean", "-fdq", cwd=wt)


def commit_task(spec: Spec, wt: Path) -> str:
    entries = changed_paths(wt)
    if not entries:
        raise RunnerError(f"{spec.id}: nothing to commit")
    bad = out_of_scope(entries, spec.allowed)
    if bad:
        raise RunnerError(f"{spec.id}: refusing to commit out-of-scope changes: {[p for _, p in bad]}")
    git("add", "--", *[p for _, p in entries], cwd=wt)
    message = f"{spec.commit}\n\nTask: {spec.id}\n"
    trailers = os.environ.get("BV_COMMIT_TRAILERS", "").strip()
    if trailers:
        message += f"{trailers}\n"
    git("commit", "-q", "-m", message, cwd=wt, env=commit_env())
    return head_of(wt)


def prepare_worktree(spec: Spec, wt: Path) -> None:
    """Flutter tasks run with --no-pub, so the package config must exist first. `flutter pub get` also rewrites
    pubspec.lock when the local SDK pins different test packages, which nobody asked for, so the lockfile is restored."""
    app = wt / "bharatverse_app"
    if "flutter" not in spec.requires or (app / ".dart_tool" / "package_config.json").exists():
        return
    print(f"[{spec.id}] preparing the Flutter package config (flutter pub get)", flush=True)
    for extra in (["--offline"], []):
        result = subprocess.run(["flutter", "pub", "get", *extra], cwd=app, env=base_env(wt), capture_output=True, text=True)
        if result.returncode == 0:
            break
    else:
        raise RunnerError("flutter pub get failed:\n" + tail(result.stdout + result.stderr))
    git("checkout", "--", "bharatverse_app/pubspec.lock", cwd=wt, check=False)
