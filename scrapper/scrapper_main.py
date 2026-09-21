"""
CLI entrypoint for the BharatVerse daily content pipeline.

Runs the full pipeline (see docs/roadmap.md, Phase 4):
AI topic selection -> multi-source scrape -> LLM article generation ->
automated validation -> Supabase persistence. Human-in-the-loop review is
explicitly deferred for now.

Usage (from the repo root or from scrapper/):
    python scrapper/scrapper_main.py
    python scrapper/scrapper_main.py --count 3
    python scrapper_main.py   (if already inside scrapper/)

Logs go to stdout as JSON lines at LOG_LEVEL (default INFO). The exit status
is 0 only if every requested article was published, so a scheduled run that
published nothing shows as failed.
"""

import argparse
import asyncio
import os
import sys
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
        "--count", type=int, default=1,
        help="Number of new articles to generate and publish (default: 1).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    configure_logging(os.environ.get("LOG_LEVEL", "INFO").upper(), "scrapper", "backend", "common")
    published = asyncio.run(run_daily_pipeline(count=args.count))
    return 0 if published >= args.count else 1


if __name__ == "__main__":
    sys.exit(main())
