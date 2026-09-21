#!/usr/bin/env python3
"""Entry point for the agent task queue runner; see agent_queue/cli.py for usage."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from agent_queue.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
