"""Tests for the agent task queue runner: a throwaway git repo, toy specs, and a stub agent instead of a model."""

import fcntl
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from agent_queue import cli, config  # noqa: E402
from agent_queue.config import RunnerError  # noqa: E402
from agent_queue.fidelity import fidelity_report  # noqa: E402
from agent_queue.spec import apply_steps, parse_spec, parse_steps  # noqa: E402
from agent_queue.worktree import changed_paths, out_of_scope  # noqa: E402

STUB = Path(__file__).with_name("stub_agent.py")
IDENTITY = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
CREATE_B = "<!-- step: create b.txt -->\n```text\nhello\n```\n"
CREATE_C = "<!-- step: create c.txt -->\n```text\nworld\n```\n"


class Queue:
    """A repo with one base commit and a directory of toy specs, with the runner pointed at both."""

    def __init__(self, root, capsys, monkeypatch):
        self.repo, self.tasks, self.agent, self.capsys = root / "repo", root / "tasks", root / "agent", capsys
        self.repo.mkdir()
        self.tasks.mkdir()
        self.git("init", "-q", "-b", "main")
        (self.repo / "a.txt").write_text("one\ntwo\n")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "base")
        for name, value in {"REPO": self.repo, "AGENT_DIR": self.agent, "TASKS_DIR": self.tasks,
                            "STOP_FILE": self.agent / "STOP", "FLUTTER_DIR": self.agent / "flutter"}.items():
            monkeypatch.setattr(config, name, value)
        monkeypatch.setattr(config.ns, "name", "queue")  # restored after the test
        config.configure("t")
        for key, value in {"BV_GIT_NAME": "t", "BV_GIT_EMAIL": "t@t", "BV_AGENT_VENV": str(root / "no-venv"),
                           "BV_AGENT_CMD": f"{sys.executable} {STUB}", "STUB_STATE": str(root / "stub.state"),
                           "STUB_LOG": str(root / "stub.log")}.items():
            monkeypatch.setenv(key, value)
        self.stub_log = root / "stub.log"

    def git(self, *args, cwd=None):
        env = {**os.environ, **IDENTITY}
        return subprocess.run(["git", *args], cwd=cwd or self.repo, env=env, capture_output=True, text=True, check=True).stdout

    def spec(self, n, steps=CREATE_B, *, allowed="b.txt", verify="test -f b.txt", depends="", requires=""):
        (self.tasks / f"TASK-{n:03d}.md").write_text(
            f"---\nid: TASK-{n:03d}\ntitle: task {n}\ndepends_on: {depends}\nrequires: {requires}\n"
            f"allowed: {allowed}\nverify: {verify}\ncommit: feat: task {n}\n---\n{steps}")

    def run(self, *args):
        code = cli.main(["--namespace", "t", *args])
        captured = self.capsys.readouterr()
        return code, captured.out, captured.err

    def subjects(self):
        return self.git("log", "--reverse", "--format=%s", "main..agent/t").splitlines()

    def dirty(self):
        return self.git("status", "--porcelain", cwd=config.ns.worktree).strip()

    def state(self, task):
        return json.loads((config.ns.state_dir / f"{task}.json").read_text())

    def prompts(self):
        return self.stub_log.read_text().split("\0")


@pytest.fixture
def q(tmp_path, capsys, monkeypatch):
    return Queue(tmp_path, capsys, monkeypatch)


def test_specs_need_front_matter_and_verify_commands(q):
    q.spec(1, depends="TASK-000", requires="git, py:json", allowed="a.txt, b.txt")
    spec = parse_spec(q.tasks / "TASK-001.md")
    assert (spec.depends_on, spec.requires, spec.allowed, spec.verify) == (
        ["TASK-000"], ["git", "py:json"], ["a.txt", "b.txt"], ["test -f b.txt"])
    (q.tasks / "TASK-002.md").write_text("no front matter\n")
    with pytest.raises(RunnerError, match="missing front matter"):
        parse_spec(q.tasks / "TASK-002.md")
    (q.tasks / "TASK-003.md").write_text("---\nid: TASK-003\ntitle: t\nallowed: a\ncommit: c\n---\n")
    with pytest.raises(RunnerError, match="no verify"):
        parse_spec(q.tasks / "TASK-003.md")


def test_steps_keep_nested_fences_and_skip_unmarked_blocks():
    text = ("```text\nignored\n```\n<!-- step: create x.md -->\n````md\n```py\ninner\n```\n````\n"
            "<!-- step: replace a.txt -->\n```text\nold\n```\n```text\nnew\n```\n<!-- step: run -->\n```bash\ntrue\n```\n")
    assert parse_steps(text) == [("create", "x.md", ["```py\ninner\n```"]), ("replace", "a.txt", ["old", "new"]),
                                 ("run", None, ["true"])]


def test_applying_steps_writes_files_and_reports_what_cannot_apply(q):
    steps = ("<!-- step: create sub/n.txt -->\n```text\nhi\n```\n<!-- step: replace a.txt -->\n```text\ntwo\n```\n"
             "```text\nTWO\n```\n<!-- step: run -->\n```bash\ntest -f sub/n.txt\n```\n")
    q.spec(1, steps)
    apply_steps(parse_spec(q.tasks / "TASK-001.md"), q.repo, dict(os.environ))
    assert (q.repo / "sub" / "n.txt").read_text() == "hi\n"
    assert (q.repo / "a.txt").read_text() == "one\nTWO\n"
    (q.repo / "a.txt").write_text("dup\ndup\n")
    for step, message in [("<!-- step: replace a.txt -->\n```text\nzzz\n```\n```text\nx\n```\n", "found 0x"),
                          ("<!-- step: replace a.txt -->\n```text\ndup\n```\n```text\nx\n```\n", "found 2x"),
                          ("<!-- step: run -->\n```bash\nfalse\n```\n", "run step failed")]:
        q.spec(2, step)
        with pytest.raises(RunnerError, match=message):
            apply_steps(parse_spec(q.tasks / "TASK-002.md"), q.repo, dict(os.environ))


def test_scope_matches_globs_across_directories():
    entries = [(" M", "src/a.py"), ("??", "docs/x.md"), ("??", "src/deep/b.py")]
    assert out_of_scope(entries, ["src/*"]) == [("??", "docs/x.md")]


def test_fidelity_compares_the_agents_files_with_what_the_steps_produce(q):
    q.spec(1, CREATE_B + "<!-- step: replace a.txt -->\n```text\ntwo\n```\n```text\nTWO\n```\n", allowed="a.txt, b.txt, c.txt")
    spec = parse_spec(q.tasks / "TASK-001.md")

    def report(spec_, files):
        q.git("reset", "-q", "--hard")
        q.git("clean", "-fdq")
        for name, text in files.items():
            (q.repo / name).write_text(text)
        return fidelity_report(spec_, q.repo, changed_paths(q.repo))

    exact = {"b.txt": "hello\n", "a.txt": "one\nTWO\n"}
    assert report(spec, exact) == ("", True)

    feedback, tolerable = report(spec, {**exact, "b.txt": "hullo\n"})
    assert not tolerable and "-hello" in feedback and "+hullo" in feedback

    feedback, tolerable = report(spec, {**exact, "b.txt": "hello\n\n"})
    assert tolerable and "empty line" in feedback

    feedback, _ = report(spec, {**exact, "c.txt": "x\n"})
    assert "c.txt" in feedback and not (q.repo / "c.txt").exists()

    q.spec(2, "<!-- step: replace a.txt -->\n```text\nnope\n```\n```text\nx\n```\n")
    assert report(parse_spec(q.tasks / "TASK-002.md"), exact) == ("", True)  # a stale spec is not the agent's fault
    q.spec(3, "prose only\n")
    assert report(parse_spec(q.tasks / "TASK-003.md"), exact) == ("", True)


def test_reference_executor_commits_one_task_per_commit_in_dependency_order(q):
    q.spec(1, depends="TASK-002")
    q.spec(2, CREATE_C, allowed="c.txt", verify="test -f c.txt")
    code, out, _ = q.run("run", "--executor", "reference", "--base", "main")
    assert code == 0
    assert q.subjects() == ["feat: task 2", "feat: task 1"]
    assert q.git("log", "--format=%B", "main..agent/t").count("Task: TASK-00") == 2
    assert q.git("show", "agent/t:c.txt") == "world\n"
    _, out, _ = q.run("run", "--executor", "reference", "--base", "main")
    assert "queue empty" in out
    assert "TASK-001  done" in q.run("list")[1]


def test_review_mode_holds_verified_work_until_it_is_committed_or_discarded(q):
    q.spec(1)
    q.spec(2, CREATE_C, allowed="c.txt", verify="test -f c.txt")
    code, out, _ = q.run("run", "--executor", "reference", "--base", "main", "--review", "--once")
    assert code == 0 and "waiting for review" in out
    assert q.state("TASK-001")["status"] == "pending" and "b.txt" in q.dirty() and q.subjects() == []
    assert "waiting for review" in q.run("run", "--executor", "reference", "--base", "main")[1]

    assert q.run("commit", "TASK-001")[0] == 0
    assert q.subjects() == ["feat: task 1"] and q.dirty() == ""
    assert not (config.ns.state_dir / "TASK-001.json").exists()

    q.run("run", "--executor", "reference", "--base", "main", "--review", "--once")
    assert q.run("discard", "TASK-002")[0] == 0
    assert q.dirty() == "" and "TASK-002  ready" in q.run("list")[1]


def test_stray_files_are_reverted_and_the_task_then_converges(q, monkeypatch):
    q.spec(1)
    monkeypatch.setenv("STUB_MODES", "stray,good")
    code, out, _ = q.run("run", "--base", "main", "--once")
    assert code == 0 and "reverted out-of-scope changes: ['z.txt']" in out and "committed" in out
    assert q.dirty() == "" and "z.txt" in q.prompts()[1]


def test_edits_to_tracked_files_outside_the_task_are_reverted(q, monkeypatch):
    q.spec(1)
    monkeypatch.setenv("STUB_MODES", "tracked,good")
    code, out, _ = q.run("run", "--base", "main", "--once")
    assert code == 0 and "reverted out-of-scope changes: ['a.txt']" in out
    assert q.git("show", "agent/t:a.txt") == "one\ntwo\n"


@pytest.mark.parametrize("modes, feedback", [
    ("blocked,nochange,good", ["You reported: BLOCKED: cannot do it", "You made no changes"]),
    ("garbage,good", ["no parseable result"]),
])
def test_blocked_claims_and_empty_attempts_are_fed_back_and_retried(q, monkeypatch, modes, feedback):
    q.spec(1)
    monkeypatch.setenv("STUB_MODES", modes)
    code, out, _ = q.run("run", "--base", "main", "--once")
    assert code == 0 and "committed" in out
    for attempt, text in enumerate(feedback, start=1):
        assert text in q.prompts()[attempt]


def test_a_task_that_never_matches_is_blocked_and_the_queue_moves_on(q, monkeypatch):
    q.spec(1)
    q.spec(2, CREATE_C, allowed="c.txt", verify="test -f c.txt", depends="TASK-001")
    q.spec(3)
    monkeypatch.setenv("STUB_MODES", "wording,wording,wording,good")
    code, out, _ = q.run("run", "--base", "main")
    assert code == 0 and "BLOCKED after 3 attempts" in out
    assert q.state("TASK-001")["status"] == "blocked" and (config.ns.log_dir / "TASK-001.failed.patch").exists()
    assert q.subjects() == ["feat: task 3"] and q.dirty() == ""  # task 2 waits on the blocked task 1
    assert "Your files do not match the task text exactly" in q.prompts()[1] and "+hullo" in q.prompts()[1]

    assert q.run("unblock", "TASK-001")[0] == 0
    assert "TASK-001  ready" in q.run("list")[1]


def test_whitespace_only_differences_are_accepted_on_the_last_attempt(q, monkeypatch):
    q.spec(1)
    monkeypatch.setenv("STUB_MODES", "blank")
    code, out, _ = q.run("run", "--base", "main", "--once")
    assert code == 0 and "accepted with whitespace-only differences" in out and q.subjects() == ["feat: task 1"]


def test_an_agent_that_moves_head_stops_the_runner(q, monkeypatch):
    q.spec(1)
    monkeypatch.setenv("STUB_MODES", "commit")
    code, _, err = q.run("run", "--base", "main")
    assert code == 2 and "moved HEAD" in err


def test_tasks_with_a_missing_requirement_are_skipped(q):
    q.spec(1, requires="no-such-tool-xyz")
    code, out, _ = q.run("run", "--executor", "reference", "--base", "main")
    assert code == 0 and "skipped: missing requirement" in out and "queue empty" in out


def test_a_second_runner_is_refused_and_a_stop_file_ends_the_loop(q):
    q.spec(1)
    q.agent.mkdir(parents=True, exist_ok=True)
    with open(q.agent / "lock", "w") as held:
        fcntl.flock(held, fcntl.LOCK_EX)
        code, _, err = q.run("list")
    assert code == 2 and "already running" in err
    (q.agent / "STOP").write_text("")
    code, out, _ = q.run("run", "--executor", "reference", "--base", "main")
    assert code == 0 and "STOP file present" in out and q.subjects() == []


def test_flutter_comes_from_flutter_root_then_the_usual_install_then_agent_dir(tmp_path, monkeypatch):
    def sdk(path):
        (path / "bin").mkdir(parents=True)
        return path

    home, agent = tmp_path / "home", tmp_path / "agent"
    monkeypatch.setattr(config, "AGENT_DIR", agent)
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: home))
    monkeypatch.delenv("FLUTTER_ROOT", raising=False)
    assert config.find_flutter() == agent / "flutter"  # nothing installed: where one would be kept

    kept = sdk(agent / "flutter")
    assert config.find_flutter() == kept
    usual = sdk(home / "flutter" / "flutter")
    assert config.find_flutter() == usual
    chosen = sdk(tmp_path / "chosen")
    monkeypatch.setenv("FLUTTER_ROOT", str(chosen))
    assert config.find_flutter() == chosen
    monkeypatch.setenv("FLUTTER_ROOT", str(tmp_path / "missing"))  # a bad override is ignored, not trusted
    assert config.find_flutter() == usual


def test_the_runners_own_package_cache_is_used_only_when_it_exists(tmp_path, monkeypatch):
    from agent_queue.shell import base_env

    sdk, cache = tmp_path / "sdk", tmp_path / "cache"
    (sdk / "bin").mkdir(parents=True)
    monkeypatch.setattr(config, "FLUTTER_DIR", sdk)
    monkeypatch.setattr(config, "PUB_CACHE", cache)
    monkeypatch.delenv("PUB_CACHE", raising=False)
    assert "PUB_CACHE" not in base_env() and base_env()["PATH"].startswith(str(sdk / "bin"))
    cache.mkdir()
    assert base_env()["PUB_CACHE"] == str(cache)

