"""Fidelity: does the agent's work match what the spec's steps produce?"""

import difflib
import tempfile
from pathlib import Path

from .config import RunnerError
from .shell import base_env, git
from .spec import Spec, apply_steps, parse_steps
from .worktree import changed_paths, revert_entries


def expected_files(spec: Spec, wt: Path):
    """{path: text} the spec's steps produce on a scratch checkout of the worktree's HEAD. None when the spec has no
    steps or does not apply to this HEAD (a stale spec is the reference executor's finding, not the agent's fault)."""
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


def significant(text: str) -> list:
    """The lines that carry meaning: no blank lines, no trailing whitespace."""
    return [line.rstrip() for line in text.splitlines() if line.strip()]


def _describe_whitespace(path: str, want: str, got: str) -> str:
    """Plain-language fix for a difference that is only blank lines or trailing spaces. A bare '-' diff line does not
    tell a small model to insert an empty line, so say which two lines the empty line belongs between."""
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
    """(feedback, tolerable). Feedback is empty when the agent's files match the spec exactly. Otherwise it is text to
    send back: a unified diff per file ('-' is the task's text, '+' the agent's), plain-language fixes for blank-line
    differences, and a note on any file changed that the task does not touch, which is reverted here. `tolerable` is
    True when only blank lines or trailing spaces differ."""
    expected = expected_files(spec, wt)
    if expected is None:
        return "", True
    problems, tolerable = [], True
    for path, want in expected.items():
        target = wt / path
        got = target.read_text() if target.exists() else ""
        if got == want:
            continue
        if significant(got) == significant(want):
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
