"""
CLI entrypoint for the BharatVerse daily content pipeline.

Runs the full pipeline (see .kiro/specs/bharatverse-mvp/roadmap.md, Phase 4):
AI topic selection -> multi-source scrape -> LLM article generation ->
automated validation -> Supabase persistence. Human-in-the-loop review is
explicitly deferred for now.

Usage (from the repo root or from scrapper/):
    python scrapper/scrapper_main.py
    python scrapper/scrapper_main.py --count 3
    python scrapper_main.py   (if already inside scrapper/)
"""

import argparse
import asyncio
import logging
import sys
from pathlib import Path

# Make both this package (`scrapper`) and the repo root (`common`, `backend`)
# importable regardless of which directory this script is invoked from.
_SCRAPPER_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _SCRAPPER_DIR.parent
for _path in (_SCRAPPER_DIR, _REPO_ROOT):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

from scrapper.scheduler import run_daily_pipeline  # noqa: E402

logging.basicConfig(level=logging.INFO)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the BharatVerse daily content pipeline.")
    parser.add_argument(
        "--count", type=int, default=1,
        help="Number of new articles to generate and publish (default: 1).",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = _parse_args()
    asyncio.run(run_daily_pipeline(count=args.count))
