#!/usr/bin/env python3
"""
Sequential runner for the agent task queue in
.kiro/specs/bharatverse-mvp/agent-tasks/.

All work happens on one integration branch (agent/queue) in a dedicated git
worktree (.agent/worktree), so the developer's own checkout is never touched.
Tasks run one at a time, in filename order, respecting `depends_on`. For each
task the runner:

  1. hands the task's spec to a local coding agent (default: `claude-local -p`)
     restricted to a small tool allowlist, or, with --executor reference,
     applies the spec's machine-readable steps itself with no model at all;
  2. checks that only files the spec allows were changed (reverting any that
     were not) and that the agent did not move HEAD itself;
  3. runs the spec's `verify:` commands itself. The agent's own claim of
     success is ignored. It also applies the spec's steps mechanically to a
     scratch checkout and diffs the agent's files against the result, so a
     dropped line or a reworded comment goes back to the agent as an exact
     diff instead of a vague test failure;
  4. makes exactly one commit per task, or with --review leaves the verified
     changes uncommitted for a human to inspect first.

Nothing is ever pushed, and the agent runs with git credentials disabled.
See the queue's README.md for the contract the agent is held to.

Usage:
    scripts/agent_loop.py list
    scripts/agent_loop.py run [--once] [--review] [--task ID] [--base REF]
    scripts/agent_loop.py run --executor reference     # no model, spec steps only
    scripts/agent_loop.py commit ID | discard ID | unblock ID | verify ID

Environment:
    BV_AGENT_CMD          agent command, default "claude-local"
    BV_AGENT_VENV         virtualenv whose bin/ goes first on PATH, default .agent/venv
    BV_AGENT_TIMEOUT      seconds one agent attempt may run, default 2400

Flutter tasks (`requires: flutter`) use the SDK in .agent/flutter and the package cache in .agent/pub-cache when
they exist. Before such a task the runner runs `flutter pub get` once per worktree and restores pubspec.lock, which a
different SDK version would otherwise rewrite.
    BV_GIT_NAME/EMAIL     commit identity, used only when git has none configured
    BV_COMMIT_TRAILERS    extra trailer lines appended to every commit message
"""

import argparse
import difflib
import fcntl
import fnmatch
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TASKS_DIR = REPO / ".kiro" / "specs" / "bharatverse-mvp" / "agent-tasks"
AGENT_DIR = REPO / ".agent"
STOP_FILE = AGENT_DIR / "STOP"
FLUTTER_DIR = AGENT_DIR / "flutter"
PUB_CACHE = AGENT_DIR / "pub-cache"
# Set by configure() from --namespace. A namespace gets its own branch, worktree,
# state and logs, so a scratch run can never touch the real queue.
BRANCH = "agent/queue"
STATE_DIR = AGENT_DIR / "state" / "queue"
LOG_DIR = AGENT_DIR / "logs" / "queue"
MAX_ATTEMPTS = 3
AGENT_TIMEOUT = int(os.environ.get("BV_AGENT_TIMEOUT", 40 * 60))  # seconds per attempt
VERIFY_TIMEOUT = 15 * 60

ALLOWED_TOOLS = [
    "Read", "Edit", "Write", "Glob", "Grep",
    "Bash(python:*)", "Bash(cd:*)", "Bash(grep:*)", "Bash(cat:*)", "Bash(ls:*)", "Bash(pwd)",
    "Bash(head:*)", "Bash(tail:*)", "Bash(git status:*)", "Bash(git diff:*)",
    "Bash(flutter:*)", "Bash(dart:*)", "Bash(./scripts/check_lcov_coverage.sh:*)",
]
DISALLOWED_TOOLS = [
    "Bash(git push:*)", "Bash(git commit:*)", "Bash(git checkout:*)", "Bash(git reset:*)",
    "Bash(git rebase:*)", "Bash(git stash:*)", "Bash(git remote:*)", "Bash(git config:*)",
    "Bash(rm:*)", "Bash(curl:*)", "Bash(wget:*)", "Bash(pip:*)", "Bash(sudo:*)",
]


class RunnerError(Exception):
    """A condition that needs a human, as opposed to a task simply failing."""


# ----------------------------------------------------------------------------
# Specs
# ----------------------------------------------------------------------------

@dataclass
class Spec:
    id: str
    title: str
    path: Path
    text: str
    depends_on: list = field(default_factory=list)
    requires: list = field(default_factory=list)
    allowed: list = field(default_factory=list)
    verify: list = field(default_factory=list)
    commit: str = ""


def configure(namespace: str) -> Path:
    """Point the module at a namespace's branch, state and logs. Returns its default worktree."""
    global BRANCH, STATE_DIR, LOG_DIR
    BRANCH = f"agent/{namespace}"
    STATE_DIR = AGENT_DIR / "state" / namespace
    LOG_DIR = AGENT_DIR / "logs" / namespace
    return AGENT_DIR / ("worktree" if namespace == "queue" else f"worktree-{namespace}")


def _csv(value):
    return [item.strip() for item in value.split(",") if item.strip()]


def parse_spec(path: Path) -> Spec:
    text = path.read_text()
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not match:
        raise RunnerError(f"{path.name}: missing front matter")
    meta = {"verify": []}
    for line in match.group(1).splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, _, value = line.partition(":")
        key, value = key.strip(), value.strip()
        if key == "verify":
            meta["verify"].append(value)
        else:
            meta[key] = value
    for required in ("id", "title", "allowed", "commit"):
        if not meta.get(required):
            raise RunnerError(f"{path.name}: front matter is missing '{required}'")
    if not meta["verify"]:
        raise RunnerError(f"{path.name}: front matter has no verify: lines")
    return Spec(
        id=meta["id"], title=meta["title"], path=path, text=text,
        depends_on=_csv(meta.get("depends_on", "")), requires=_csv(meta.get("requires", "")),
        allowed=_csv(meta["allowed"]), verify=meta["verify"], commit=meta["commit"],
    )


def load_specs(tasks_dir: Path = None) -> list:
    specs = [parse_spec(p) for p in sorted((tasks_dir or TASKS_DIR).glob("TASK-*.md"))]
    ids = [s.id for s in specs]
    if len(set(ids)) != len(ids):
        raise RunnerError("duplicate task ids in the queue")
    for spec in specs:
        for dep in spec.depends_on:
            if dep not in ids:
                raise RunnerError(f"{spec.id} depends on unknown task {dep}")
    return specs


# ----------------------------------------------------------------------------
# Machine-readable steps (used by the reference executor)
# ----------------------------------------------------------------------------

STEP_RE = re.compile(r"^<!-- step: (create|replace|run)(?: (.+?))? -->\s*$")
FENCE_RE = re.compile(r"^(`{3,})[\w-]*\s*$")


def parse_steps(text: str) -> list:
    """Return [(kind, arg, [block, ...])]. `replace` takes two fenced blocks
    (old, new); `create` and `run` take one. A fence may use more than three
    backticks so its content can itself contain fenced code."""
    lines = text.splitlines()
    steps, pending, i = [], None, 0
    while i < len(lines):
        marker = STEP_RE.match(lines[i])
        fence = FENCE_RE.match(lines[i])
        if marker:
            kind, arg = marker.group(1), marker.group(2)
            pending = (kind, arg, 2 if kind == "replace" else 1, [])
        elif fence:
            ticks = fence.group(1)
            body, i = [], i + 1
            while i < len(lines) and not re.fullmatch(rf"`{{{len(ticks)},}}\s*", lines[i]):
                body.append(lines[i])
                i += 1
            if pending:  # fenced blocks that no marker is waiting for are skipped whole
                pending[3].append("\n".join(body))
                if len(pending[3]) == pending[2]:
                    steps.append((pending[0], pending[1], pending[3]))
                    pending = None
        i += 1
    return steps


def apply_steps(spec: Spec, root: Path, env: dict) -> None:
    """Apply a spec's steps exactly as a perfectly obedient agent would."""
    steps = parse_steps(spec.text)
    if not steps:
        raise RunnerError(f"{spec.id}: no machine-readable steps to apply")
    for kind, arg, blocks in steps:
        if kind == "create":
            target = root / arg
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(blocks[0] + "\n")
        elif kind == "replace":
            target = root / arg
            old, new = blocks
            content = target.read_text()
            if content.count(old) != 1:
                raise RunnerError(f"{spec.id}: replace text found {content.count(old)}x (need 1x) in {arg}")
            target.write_text(content.replace(old, new))
        else:
            result = subprocess.run(["bash", "-c", blocks[0]], cwd=root, env=env, capture_output=True, text=True)
            if result.returncode != 0:
                raise RunnerError(f"{spec.id}: run step failed:\n{tail(result.stdout + result.stderr)}")


# ----------------------------------------------------------------------------
# Git and process helpers
# ----------------------------------------------------------------------------

def tail(text: str, lines: int = 60) -> str:
    return "\n".join(text.strip().splitlines()[-lines:])


def git(*args, cwd, check=True, env=None):
    result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, env=env)
    if check and result.returncode != 0:
        raise RunnerError(f"git {' '.join(args)} failed in {cwd}:\n{result.stderr.strip()}")
    return result


def venv_dir() -> Path:
    return Path(os.environ.get("BV_AGENT_VENV") or AGENT_DIR / "venv")


def base_env(root: Path = None) -> dict:
    """Environment for verify commands and spec steps. BV_ROOT lets every spec command start with
    `cd "$BV_ROOT"`, so it works no matter which directory the agent's persistent shell is in."""
    env = dict(os.environ)
    if root is not None:
        env["BV_ROOT"] = str(root)
    if (FLUTTER_DIR / "bin").is_dir():
        env["PATH"] = f"{FLUTTER_DIR / 'bin'}{os.pathsep}{env['PATH']}"
        env["PUB_CACHE"] = str(PUB_CACHE)
        env["FLUTTER_SUPPRESS_ANALYTICS"] = "true"
        env["CI"] = "true"  # makes Flutter and Dart non-interactive
    venv_bin = venv_dir() / "bin"
    if venv_bin.is_dir():  # added last, so the project's Python is always found first
        env["PATH"] = f"{venv_bin}{os.pathsep}{env['PATH']}"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


def agent_env(root: Path) -> dict:
    """The agent's environment: same as ours, but nothing it runs can reach a remote."""
    env = base_env(root)
    env.pop("SSH_AUTH_SOCK", None)
    env.update({
        "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "/bin/false", "GIT_SSH_COMMAND": "/bin/false",
        "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "credential.helper", "GIT_CONFIG_VALUE_0": "",
    })
    return env


def commit_env() -> dict:
    env = dict(os.environ)
    if not git("config", "user.email", cwd=REPO, check=False).stdout.strip():
        name, email = os.environ.get("BV_GIT_NAME"), os.environ.get("BV_GIT_EMAIL")
        if not (name and email):
            raise RunnerError("git has no identity configured; set BV_GIT_NAME and BV_GIT_EMAIL for this run")
        env.update(GIT_AUTHOR_NAME=name, GIT_AUTHOR_EMAIL=email, GIT_COMMITTER_NAME=name, GIT_COMMITTER_EMAIL=email)
    return env


def ensure_worktree(wt: Path, base: str) -> None:
    if (wt / ".git").exists():
        return
    wt.parent.mkdir(parents=True, exist_ok=True)
    branch_exists = git("rev-parse", "--verify", "--quiet", f"refs/heads/{BRANCH}", cwd=REPO, check=False).returncode == 0
    if branch_exists:
        git("worktree", "add", str(wt), BRANCH, cwd=REPO)
    else:
        git("worktree", "add", "-b", BRANCH, str(wt), base, cwd=REPO)


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
    branch_exists = git("rev-parse", "--verify", "--quiet", f"refs/heads/{BRANCH}", cwd=REPO, check=False).returncode == 0
    if not branch_exists:
        return set()
    log = git("log", BRANCH, "--format=%B", cwd=REPO).stdout
    return set(re.findall(r"(?m)^Task: (TASK-\d+)\s*$", log))


# ----------------------------------------------------------------------------
# State (kept outside the specs and outside git)
# ----------------------------------------------------------------------------

def state_file(task_id: str) -> Path:
    return STATE_DIR / f"{task_id}.json"


def load_state(task_id: str) -> dict:
    path = state_file(task_id)
    return json.loads(path.read_text()) if path.exists() else {}


def save_state(task_id: str, **fields) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
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


# ----------------------------------------------------------------------------
# Fidelity: does the agent's work match what the spec's steps produce?
# ----------------------------------------------------------------------------

def expected_files(spec: Spec, wt: Path):
    """What applying the spec's steps mechanically to a scratch checkout of the worktree's HEAD produces, as
    {path: text}. None when the spec has no steps, or does not apply cleanly to this HEAD (a stale spec is
    reported by the reference executor, not held against the agent)."""
    if not parse_steps(spec.text):
        return None
    with tempfile.TemporaryDirectory(prefix="fidelity-") as tmp:
        scratch = Path(tmp) / "wt"
        git("worktree", "add", "--detach", str(scratch), "HEAD", cwd=wt)
        try:
            apply_steps(spec, scratch, base_env(scratch))
            return {path: (scratch / path).read_text() for _, path in changed_paths(scratch) if (scratch / path).exists()}
        except RunnerError:
            return None
        finally:
            git("worktree", "remove", "--force", str(scratch), cwd=wt, check=False)


def _significant(text: str) -> list:
    """The lines that carry meaning: no blank lines, no trailing whitespace."""
    return [line.rstrip() for line in text.splitlines() if line.strip()]


def _describe_whitespace(path: str, want: str, got: str) -> str:
    """Plain-language instructions for a difference that is only blank lines or trailing spaces. A bare '-' line in a
    diff does not tell a small model to insert an empty line, so say which two lines the empty line belongs between."""
    a, b = want.splitlines(), got.splitlines()
    notes = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if tag == "equal":
            continue
        if tag == "delete" and not any(line.strip() for line in a[i1:i2]):
            before = a[i1 - 1] if i1 else "(the top of the file)"
            after = a[i2] if i2 < len(a) else "(the end of the file)"
            notes.append(f"In {path}, insert {i2 - i1} empty line(s) between these two lines:\n  {before}\n  {after}")
        elif tag == "insert" and not any(line.strip() for line in b[j1:j2]):
            before = b[j1 - 1] if j1 else "(the top of the file)"
            notes.append(f"In {path}, remove the {j2 - j1} extra empty line(s) that follow this line:\n  {before}")
        else:
            notes.append(f"In {path}, trailing spaces differ on the line(s): {[line.rstrip() for line in a[i1:i2]]}. "
                         "Remove trailing spaces.")
    return "\n".join(notes)


def fidelity_report(spec: Spec, wt: Path, entries: list) -> tuple:
    """(feedback, tolerable). Feedback is empty when the agent's files match the spec exactly. Otherwise it is text
    to send back: a unified diff per file ('-' lines are the task's text, '+' lines are the agent's), plain-language
    instructions where the only difference is blank lines, and a note on any file it changed that the task does not
    touch. Such a stray change is reverted here, because it can only be a mistake. `tolerable` is True when nothing
    that carries meaning differs, only blank lines or trailing spaces."""
    expected = expected_files(spec, wt)
    if expected is None:
        return "", True
    problems, tolerable = [], True
    for path, want in expected.items():
        target = wt / path
        got = target.read_text() if target.exists() else ""
        if got == want:
            continue
        if _significant(got) == _significant(want):
            problems.append(_describe_whitespace(path, want, got))
            continue
        tolerable = False
        diff = difflib.unified_diff(want.splitlines(), got.splitlines(), f"{path} (task text)", f"{path} (yours)",
                                    lineterm="", n=2)
        problems.append("\n".join(list(diff)[:60]))
    stray = [(status, path) for status, path in entries if path not in expected]
    if stray:
        revert_entries(wt, stray)
        problems.append("You changed files the task does not change, and they were reverted: "
                        f"{[path for _, path in stray]}.")
    if not problems:
        return "", True
    return ("Your files do not match the task text exactly. Lines starting with '-' are the task's text and lines "
            "starting with '+' are yours. Change only what differs, and touch nothing else.\n\n"
            + "\n\n".join(problems)), tolerable


# ----------------------------------------------------------------------------
# Running one task
# ----------------------------------------------------------------------------

def build_prompt(spec: Spec, feedback: str, wt: Path) -> str:
    prompt = f"""You are an autonomous coding agent executing ONE task from a queue.
Your working directory is a git worktree of the project. Follow the task below exactly.

Rules, enforced by a runner that checks your work independently:
- Change only the files listed under `allowed` in the front matter. Anything else is reverted.
- Do not explore the repository. Read only what the task tells you to read.
- Do not run git commit, checkout, reset, push, or any git command that changes state. The runner commits.
- The sandbox denies shell redirections and pipes such as `2>&1` and `|`, `$?`, `curl`, and anything not listed as
  allowed. Run each command exactly as written, on its own, and read its output. A denied command is not worth retrying.
- Do not invent API calls or edit text you were not told to edit. If a step cannot be done as written, stop.
- Copy code blocks exactly. Do not "improve" them.
- Your shell remembers its directory between commands. Every command in this task already starts with a
  `cd` to the worktree root, so run commands exactly as written and they work from anywhere.
- Each step is marked by an HTML comment above its fenced block(s):
    `create PATH`   write PATH with exactly the fenced content (Read an existing file first, then Write).
    `replace PATH`  in PATH, replace the first fenced block with the second, exactly (Read first, then Edit).
    `run`           run the fenced command exactly, with Bash.
- When the steps are done, run every `verify:` command from the front matter and fix what fails.
- Finish with exactly one line: `DONE`, or `BLOCKED: <one-line reason>`.

=== TASK ({spec.id}) ===
{spec.text.replace("$BV_ROOT", str(wt))}
=== END TASK ===
"""
    if feedback:
        prompt += f"\nFEEDBACK FROM THE PREVIOUS ATTEMPT (fix this, keep the parts that already work):\n{feedback}\n"
    return prompt


def run_agent(spec: Spec, wt: Path, feedback: str, attempt: int) -> str:
    """Run the agent once. Returns its final message, or a BLOCKED line if it timed out or crashed."""
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    cmd = shlex.split(os.environ.get("BV_AGENT_CMD", "claude-local")) + [
        "-p", build_prompt(spec, feedback, wt),
        "--permission-mode", "dontAsk", "--no-session-persistence", "--output-format", "json",
        "--allowedTools", *ALLOWED_TOOLS, "--disallowedTools", *DISALLOWED_TOOLS,
    ]
    log = LOG_DIR / f"{spec.id}.attempt{attempt}.json"
    try:
        result = subprocess.run(cmd, cwd=wt, env=agent_env(wt), stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=AGENT_TIMEOUT)
    except subprocess.TimeoutExpired:
        return f"BLOCKED: agent timed out after {AGENT_TIMEOUT} seconds"
    log.write_text(result.stdout + ("\n--- stderr ---\n" + result.stderr if result.stderr else ""))
    try:
        return str(json.loads(result.stdout).get("result", "")).strip()
    except (json.JSONDecodeError, AttributeError):
        return f"BLOCKED: agent produced no parseable result (exit {result.returncode})"


def run_verify(spec: Spec, wt: Path) -> tuple:
    env = base_env(wt)
    for command in spec.verify:
        try:
            result = subprocess.run(["bash", "-c", command], cwd=wt, env=env, capture_output=True,
                                    text=True, timeout=VERIFY_TIMEOUT)
        except subprocess.TimeoutExpired:
            return False, f"$ {command}\ntimed out after {VERIFY_TIMEOUT // 60} minutes"
        if result.returncode != 0:
            return False, f"$ {command}\n(exit {result.returncode})\n{tail(result.stdout + chr(10) + result.stderr)}"
    return True, ""


def snapshot_patch(spec: Spec, wt: Path, suffix: str) -> Path:
    """Write the worktree's uncommitted changes (untracked files included) to a patch file."""
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    git("add", "-A", cwd=wt)
    patch = git("diff", "--cached", "HEAD", cwd=wt).stdout
    git("reset", "-q", cwd=wt)
    target = LOG_DIR / f"{spec.id}.{suffix}.patch"
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
    """Flutter tasks run with --no-pub, so the package config has to exist first. `flutter pub get` also rewrites
    the committed pubspec.lock when the SDK pins different test packages than the one it was created with, which is
    an artifact of the SDK here, not a change anyone asked for, so the lockfile is restored."""
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


def run_task(spec: Spec, wt: Path, executor: str, review: bool, feedback: str = "") -> bool:
    """Execute one task. True if it ended verified (committed, or pending review)."""
    prepare_worktree(spec, wt)
    resuming = load_state(spec.id).get("status") == "pending"
    if not resuming and changed_paths(wt):
        raise RunnerError(f"worktree {wt} has uncommitted changes; resolve them before starting {spec.id}")

    if resuming:
        kept = snapshot_patch(spec, wt, "pending")
        print(f"[{spec.id}] verified work saved to {kept} before applying feedback", flush=True)
    head = head_of(wt)
    notes = feedback
    for attempt in range(1, MAX_ATTEMPTS + 1):
        print(f"[{spec.id}] attempt {attempt}/{MAX_ATTEMPTS} ({executor})", flush=True)
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
            notes = ("You changed files that are not allowed; they were reverted: "
                     f"{[p for _, p in bad]}. Change only: {spec.allowed}.")
            print(f"[{spec.id}]   reverted out-of-scope changes: {[p for _, p in bad]}", flush=True)
            continue
        if claim.startswith("BLOCKED"):
            notes = f"You reported: {claim}"
            print(f"[{spec.id}]   agent reported blocked: {claim}", flush=True)
            continue
        if not entries:
            notes = "You made no changes. Follow the steps and change the allowed files."
            print(f"[{spec.id}]   no changes made", flush=True)
            continue

        fidelity, tolerable = ("", True) if executor == "reference" else fidelity_report(spec, wt, entries)
        ok, failure = run_verify(spec, wt)
        # Blank lines and trailing spaces are cosmetic. If they are all that is left on the last attempt and the
        # checks pass, take the work rather than block a task over them.
        if ok and fidelity and tolerable and attempt == MAX_ATTEMPTS:
            print(f"[{spec.id}]   accepted with whitespace-only differences from the task text:\n{fidelity}", flush=True)
            fidelity = ""
        if ok and not fidelity:
            if review:
                save_state(spec.id, status="pending", attempts=attempt)
                print(f"[{spec.id}] verified, waiting for review. `agent_loop.py commit {spec.id}` to accept.", flush=True)
                return True
            sha = commit_task(spec, wt)
            clear_state(spec.id)
            print(f"[{spec.id}] committed {sha[:7]}", flush=True)
            return True
        parts = []
        if not ok:
            parts.append(f"Verification failed:\n{failure}")
            print(f"[{spec.id}]   verification failed:\n{failure}", flush=True)
        if fidelity:
            parts.append(fidelity)
            print(f"[{spec.id}]   does not match the task text:\n{fidelity}", flush=True)
        notes = "\n\n".join(parts)

    snapshot_patch(spec, wt, "failed")
    discard_changes(wt)
    save_state(spec.id, status="blocked", attempts=MAX_ATTEMPTS, reason=notes)
    saved = LOG_DIR / f"{spec.id}.failed.patch"
    print(f"[{spec.id}] BLOCKED after {MAX_ATTEMPTS} attempts; patch saved to {saved}", flush=True)
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


# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

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


def find(specs, task_id):
    for spec in specs:
        if spec.id == task_id:
            return spec
    raise RunnerError(f"unknown task {task_id}")


def cmd_run(args, specs):
    wt = Path(args.worktree).resolve()
    if args.dry_run:
        spec, reason = (find(specs, args.task), "") if args.task else next_task(specs)
        print(build_prompt(spec, args.feedback, wt) if spec else reason)
        return 0
    ensure_worktree(wt, args.base)
    last_reason = None
    while True:
        if STOP_FILE.exists():
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
    sha = commit_task(spec, wt)
    clear_state(spec.id)
    print(f"[{spec.id}] committed {sha[:7]}")
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


def main(argv=None) -> int:
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
    args = parser.parse_args(argv)
    args.command = args.command or "list"
    default_worktree = configure(args.namespace)
    args.worktree = args.worktree or str(default_worktree)

    AGENT_DIR.mkdir(exist_ok=True)
    lock = open(AGENT_DIR / "lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("another agent_loop.py is already running", file=sys.stderr)
        return 2
    try:
        specs = load_specs()
        handler = {"list": cmd_list, "run": cmd_run, "commit": cmd_commit, "discard": cmd_discard,
                   "unblock": cmd_unblock, "verify": cmd_verify}[args.command]
        return handler(args, specs) or 0
    except RunnerError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
