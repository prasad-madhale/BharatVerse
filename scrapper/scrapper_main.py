"""
Phase 0 minimal runner for the BharatVerse content pipeline.

Hardcodes a single topic and runs it through scrape -> generate, printing
the resulting Article as JSON. This is the smallest possible slice of the
pipeline (see .kiro/specs/bharatverse-mvp/roadmap.md, Phase 0) -- no
content validation, topic selection, or storage yet; those are Phase 4.

Usage (from the repo root or from scrapper/):
    python scrapper/scrapper_main.py
    python scrapper_main.py   (if already inside scrapper/)
"""

import asyncio
import logging
import sys
from pathlib import Path

# Make both this package (`scrapper`) and the repo root (`common`) importable
# regardless of which directory this script is invoked from.
_SCRAPPER_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _SCRAPPER_DIR.parent
for _path in (_SCRAPPER_DIR, _REPO_ROOT):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

from scrapper import ArticleGenerator, WebScraper  # noqa: E402

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Hardcoded for Phase 0 -- real topic selection is a Phase 4 (scheduler) concern.
TOPIC = "Mauryan Empire"


async def run(topic: str = TOPIC) -> None:
    scraper = WebScraper()
    logger.info(f"Scraping '{topic}'...")
    scraped = await scraper.search_and_scrape(topic, sources=["wikipedia"])
    if not scraped:
        logger.error(f"No content scraped for '{topic}', aborting")
        return
    logger.info(f"Scraped {len(scraped)} page(s)")

    generator = ArticleGenerator()
    logger.info("Generating article...")
    article = await generator.generate_article(scraped, topic=topic)

    print(article.model_dump_json(indent=2))


if __name__ == "__main__":
    asyncio.run(run())
