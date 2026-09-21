"""Task specs: front matter, and the machine-readable steps the reference executor applies."""

import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from . import config
from .config import RunnerError
from .shell import tail

STEP_RE = re.compile(r"^<!-- step: (create|replace|run)(?: (.+?))? -->\s*$")
FENCE_RE = re.compile(r"^(`{3,})[\w-]*\s*$")


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
    specs = [parse_spec(p) for p in sorted((tasks_dir or config.TASKS_DIR).glob("TASK-*.md"))]
    ids = [s.id for s in specs]
    if len(set(ids)) != len(ids):
        raise RunnerError("duplicate task ids in the queue")
    for spec in specs:
        for dep in spec.depends_on:
            if dep not in ids:
                raise RunnerError(f"{spec.id} depends on unknown task {dep}")
    return specs


def parse_steps(text: str) -> list:
    """[(kind, arg, [block, ...])]. `replace` takes two fenced blocks (old, new); `create` and `run` take one.
    A fence may use more than three backticks so its content can itself contain fenced code."""
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
