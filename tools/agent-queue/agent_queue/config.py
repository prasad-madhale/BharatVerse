"""Paths, limits, and the per-namespace branch, worktree, state and log locations."""

import os
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
TASKS_DIR = Path(__file__).resolve().parents[1] / "tasks"
AGENT_DIR = REPO / ".agent"
STOP_FILE = AGENT_DIR / "STOP"
PUB_CACHE = AGENT_DIR / "pub-cache"  # used only when a Flutter SDK is kept under .agent/


def find_flutter() -> Path:
    """The Flutter SDK: $FLUTTER_ROOT, else the usual install at ~/flutter/flutter, else a copy kept under .agent/."""
    for candidate in (os.environ.get("FLUTTER_ROOT"), Path.home() / "flutter" / "flutter", AGENT_DIR / "flutter"):
        if candidate and (Path(candidate) / "bin").is_dir():
            return Path(candidate)
    return AGENT_DIR / "flutter"


FLUTTER_DIR = find_flutter()
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


@dataclass
class Namespace:
    """Each namespace has its own branch, worktree, state and logs, so a scratch run never touches the real queue."""

    name: str = "queue"

    @property
    def branch(self) -> str:
        return f"agent/{self.name}"

    @property
    def state_dir(self) -> Path:
        return AGENT_DIR / "state" / self.name

    @property
    def log_dir(self) -> Path:
        return AGENT_DIR / "logs" / self.name

    @property
    def worktree(self) -> Path:
        return AGENT_DIR / ("worktree" if self.name == "queue" else f"worktree-{self.name}")


ns = Namespace()


def configure(name: str) -> Path:
    """Select a namespace; returns its default worktree."""
    ns.name = name
    return ns.worktree
