"""
CLI entrypoint for the BharatVerse daily content pipeline.

Runs the full pipeline (see docs/roadmap.md, Phase 4):
AI topic selection -> multi-source scrape -> LLM article generation ->
automated validation -> Supabase persistence. Human-in-the-loop review is
explicitly deferred for now.

Usage (from the repo root or from scrapper/):
    python scrapper/scrapper_main.py
    python scrapper/scrapper_main.py --count 3
    python scrapper/scrapper_main.py --publish-on 2026-10-20   # goes live that day (India), not before
    python scrapper/scrapper_main.py --backlog 7               # one on each of the next 7 free days
    python scrapper_main.py   (if already inside scrapper/)

Logs go to stdout as JSON lines at LOG_LEVEL (default INFO). The exit status
is 0 only if every requested article was published, so a scheduled run that
published nothing shows as failed.
"""

import argparse
import asyncio
import os
import sys
from datetime import date
from pathlib import Path

# Make both this package (`scrapper`) and the repo root (`common`, `backend`)
# importable regardless of which directory this script is invoked from.
_SCRAPPER_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _SCRAPPER_DIR.parent
for _path in (_SCRAPPER_DIR, _REPO_ROOT):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

from common.logging_config import configure_logging  # noqa: E402
from scrapper.scheduler import run_daily_pipeline  # noqa: E402


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the BharatVerse daily content pipeline.")
    parser.add_argument(
        "--count", type=int,
        help="Number of new articles to generate and publish (default: 1).",
    )
    parser.add_argument(
        "--publish-on", type=date.fromisoformat, metavar="YYYY-MM-DD",
        help="The day they go live, in India (default: today); a later day schedules them.",
    )
    parser.add_argument(
        "--backlog", type=int, metavar="N",
        help="Instead, schedule N articles, one on each of the next N days after today with no article.",
    )
    args = parser.parse_args(argv)
    if args.backlog is not None and (args.count is not None or args.publish_on is not None):
        parser.error("--backlog picks its own days and count; leave out --count and --publish-on")
    if args.backlog is not None and args.backlog < 1:
        parser.error("--backlog needs at least 1")
    return args


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    configure_logging(os.environ.get("LOG_LEVEL", "INFO").upper(), "scrapper", "backend", "common")
    wanted = args.backlog or args.count or 1
    published = asyncio.run(run_daily_pipeline(
        count=args.count or 1, publish_on=args.publish_on, backlog=args.backlog or 0,
    ))
    return 0 if published >= wanted else 1


if __name__ == "__main__":
    sys.exit(main())
