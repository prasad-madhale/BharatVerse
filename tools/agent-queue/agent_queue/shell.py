"""Subprocess and environment helpers."""

import os
import subprocess
from pathlib import Path

from . import config
from .config import RunnerError


def tail(text: str, lines: int = 60) -> str:
    return "\n".join(text.strip().splitlines()[-lines:])


def git(*args, cwd, check=True, env=None):
    result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, env=env)
    if check and result.returncode != 0:
        raise RunnerError(f"git {' '.join(args)} failed in {cwd}:\n{result.stderr.strip()}")
    return result


def venv_dir() -> Path:
    return Path(os.environ.get("BV_AGENT_VENV") or config.AGENT_DIR / "venv")


def base_env(root: Path = None) -> dict:
    """Environment for verify commands and spec steps. BV_ROOT lets a spec command start with `cd "$BV_ROOT"`."""
    env = dict(os.environ)
    if root is not None:
        env["BV_ROOT"] = str(root)
    if (config.FLUTTER_DIR / "bin").is_dir():
        env["PATH"] = f"{config.FLUTTER_DIR / 'bin'}{os.pathsep}{env['PATH']}"
        if config.PUB_CACHE.is_dir():  # a cache kept for an SDK under .agent/; any other SDK uses its own default
            env["PUB_CACHE"] = str(config.PUB_CACHE)
        env["FLUTTER_SUPPRESS_ANALYTICS"] = "true"
        env["CI"] = "true"  # makes Flutter and Dart non-interactive
    venv_bin = venv_dir() / "bin"
    if venv_bin.is_dir():  # added last, so the project's Python is always found first
        env["PATH"] = f"{venv_bin}{os.pathsep}{env['PATH']}"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


def agent_env(root: Path) -> dict:
    """The agent's environment: ours, minus anything that lets it reach a remote."""
    env = base_env(root)
    env.pop("SSH_AUTH_SOCK", None)
    env.update({
        "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "/bin/false", "GIT_SSH_COMMAND": "/bin/false",
        "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "credential.helper", "GIT_CONFIG_VALUE_0": "",
    })
    return env


def commit_env() -> dict:
    env = dict(os.environ)
    if not git("config", "user.email", cwd=config.REPO, check=False).stdout.strip():
        name, email = os.environ.get("BV_GIT_NAME"), os.environ.get("BV_GIT_EMAIL")
        if not (name and email):
            raise RunnerError("git has no identity configured; set BV_GIT_NAME and BV_GIT_EMAIL for this run")
        env.update(GIT_AUTHOR_NAME=name, GIT_AUTHOR_EMAIL=email, GIT_COMMITTER_NAME=name, GIT_COMMITTER_EMAIL=email)
    return env
