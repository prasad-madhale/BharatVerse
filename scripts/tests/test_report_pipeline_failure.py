"""Tests for report_pipeline_failure.sh with a stub `gh` that records its calls and fakes an open issue or a label."""

import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "report_pipeline_failure.sh"
RUN = "https://github.com/o/r/actions/runs/42"

STUB_GH = """#!/bin/bash
printf '%s\\n' "$*" >> "$CALLS"
case "$1 $2" in
  "label create") [ -n "$LABEL_EXISTS" ] && exit 1 ;;
  "issue list") printf '%s\\n' "$OPEN_ISSUE" ;;
  "issue create") [ -n "$CREATE_FAILS" ] && exit 1 ;;
esac
exit 0
"""


@pytest.fixture
def run(tmp_path):
    """run(**env) runs the script and returns (exit code, the gh commands it made)."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "gh").write_text(STUB_GH)
    (bin_dir / "gh").chmod(0o755)
    calls = tmp_path / "calls.txt"

    def go(**extra):
        env = {"PATH": f"{bin_dir}:/usr/bin:/bin", "CALLS": str(calls), "RUN_URL": RUN,
               "GITHUB_REPOSITORY": "o/r", "OPEN_ISSUE": "", **extra}
        done = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)
        return done.returncode, calls.read_text().splitlines() if calls.exists() else []

    return go


def test_a_first_failure_opens_a_labelled_issue_linking_the_run(run):
    code, calls = run()

    assert code == 0
    created = [c for c in calls if c.startswith("issue create")]
    assert len(created) == 1
    assert "--label pipeline-failure" in created[0] and RUN in created[0] and "--repo o/r" in created[0]
    assert not [c for c in calls if c.startswith("issue comment")]


def test_a_repeat_failure_comments_on_the_open_issue_instead(run):
    code, calls = run(OPEN_ISSUE="7")

    assert code == 0
    assert [c for c in calls if c.startswith("issue comment")] == [f"issue comment 7 --repo o/r --body Failed again: {RUN}"]
    assert not [c for c in calls if c.startswith("issue create")]


def test_an_existing_label_is_not_an_error(run):
    code, calls = run(LABEL_EXISTS="1")

    assert code == 0
    assert any(c.startswith("issue create") for c in calls)


def test_a_failure_to_open_the_issue_fails_the_step(run):
    code, _ = run(CREATE_FAILS="1")

    assert code != 0
