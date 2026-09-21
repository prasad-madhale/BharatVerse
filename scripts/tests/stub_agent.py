#!/usr/bin/env python3
"""Stand-in for the coding agent. Each invocation behaves as the next entry of STUB_MODES (comma-separated) says,
and appends the prompt it was given to STUB_LOG."""
import json
import os
import subprocess
import sys
from pathlib import Path

state = Path(os.environ["STUB_STATE"])
attempt = int(state.read_text()) if state.exists() else 0
state.write_text(str(attempt + 1))
modes = os.environ["STUB_MODES"].split(",")
mode = modes[min(attempt, len(modes) - 1)]
with open(os.environ["STUB_LOG"], "a") as log:
    log.write(sys.argv[sys.argv.index("-p") + 1] + "\0")

claim = "DONE"
if mode == "good":
    Path("b.txt").write_text("hello\n")
elif mode == "wording":
    Path("b.txt").write_text("hullo\n")
elif mode == "blank":  # only a blank line differs from the task text
    Path("b.txt").write_text("hello\n\n")
elif mode == "stray":
    Path("b.txt").write_text("hello\n")
    Path("z.txt").write_text("stray\n")
elif mode == "tracked":  # also edits a tracked file the task does not allow
    Path("b.txt").write_text("hello\n")
    Path("a.txt").write_text("changed\n")
elif mode == "blocked":
    claim = "BLOCKED: cannot do it"
elif mode == "commit":
    Path("b.txt").write_text("hello\n")
    subprocess.run(["git", "add", "-A"], check=True)
    subprocess.run(["git", "-c", "user.name=x", "-c", "user.email=x@x", "commit", "-qm", "sneaky"], check=True)
elif mode == "garbage":
    print("not json")
    sys.exit(1)
print(json.dumps({"result": claim}))  # "nochange" falls through to here
