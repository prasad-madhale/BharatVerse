"""Running the local coding agent on one task."""

import json
import os
import shlex
import subprocess
from pathlib import Path

from . import config
from .shell import agent_env
from .spec import Spec


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
    config.ns.log_dir.mkdir(parents=True, exist_ok=True)
    cmd = shlex.split(os.environ.get("BV_AGENT_CMD", "claude-local")) + [
        "-p", build_prompt(spec, feedback, wt),
        "--permission-mode", "dontAsk", "--no-session-persistence", "--output-format", "json",
        "--allowedTools", *config.ALLOWED_TOOLS, "--disallowedTools", *config.DISALLOWED_TOOLS,
    ]
    log = config.ns.log_dir / f"{spec.id}.attempt{attempt}.json"
    try:
        result = subprocess.run(cmd, cwd=wt, env=agent_env(wt), stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=config.AGENT_TIMEOUT)
    except subprocess.TimeoutExpired:
        return f"BLOCKED: agent timed out after {config.AGENT_TIMEOUT} seconds"
    log.write_text(result.stdout + ("\n--- stderr ---\n" + result.stderr if result.stderr else ""))
    try:
        return str(json.loads(result.stdout).get("result", "")).strip()
    except (json.JSONDecodeError, AttributeError):
        return f"BLOCKED: agent produced no parseable result (exit {result.returncode})"
