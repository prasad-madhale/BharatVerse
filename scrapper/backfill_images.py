"""
CLI entrypoint to attach images to already-published articles that have none -- run once after
image_sourcing.py landed, since only articles generated after that point get images automatically.

Usage (from the repo root or from scrapper/):
    python scrapper/backfill_images.py
    python scrapper/backfill_images.py --all       # re-source every article, not just imageless ones
    python backfill_images.py                      # if already inside scrapper/

Re-sources using the article's own Wikipedia citation as the topic -- the article's title is an
LLM-written headline (e.g. "Haldighati, 1576: The Battle Nobody Can Agree On"), not the real
Wikipedia title it was generated from ("Battle of Haldighati"), and image_sourcing.py's Wikipedia
lookup needs the real one. No re-scraping, re-generation, or re-review, only the image step runs.
Idempotent per article (ArticleService.save_article overwrites), so a failed run can just be
re-run.
"""

import argparse
import asyncio
import logging
import os
import sys
from pathlib import Path
from urllib.parse import unquote

# Make both this package (`scrapper`) and the repo root (`common`, `backend`)
# importable regardless of which directory this script is invoked from.
_SCRAPPER_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _SCRAPPER_DIR.parent
for _path in (_SCRAPPER_DIR, _REPO_ROOT):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

from backend.services.article_service import ArticleService  # noqa: E402
from common.logging_config import configure_logging  # noqa: E402
from scrapper.image_sourcing import ImageSourcer  # noqa: E402

logger = logging.getLogger(__name__)


def _topic_for(article) -> str:
    """The real Wikipedia title the article was generated from, recovered from its own
    Wikipedia citation, falling back to the article's (LLM-written headline) title when there
    is no Wikipedia citation to recover it from."""
    for citation in article.citations:
        if citation.source_name == "wikipedia":
            title = citation.source_url.rstrip("/").rsplit("/", 1)[-1]
            return unquote(title).replace("_", " ")
    return article.title


async def backfill(all_articles: bool = False) -> int:
    """Returns how many articles were successfully given at least one image."""
    article_service = ArticleService()
    image_sourcer = ImageSourcer()

    if all_articles:
        ids = []
        offset = 0
        while batch := await article_service.list_recent_articles(limit=100, offset=offset):
            ids.extend(a.id for a in batch)
            offset += 100
    else:
        ids = await article_service.list_ids_missing_images()

    logger.info(f"Backfilling images for {len(ids)} article(s)")
    updated = 0
    for article_id in ids:
        article = await article_service.get_article_by_id(article_id)
        if article is None:
            logger.warning(f"{article_id} disappeared, skipping")
            continue
        topic = _topic_for(article)
        try:
            images = await image_sourcer.source_images(article, topic=topic)
        except Exception:
            logger.warning(f"Image sourcing failed for {article_id} ('{topic}')", exc_info=True)
            continue
        if not images:
            logger.warning(f"No usable images found for {article_id} (topic '{topic}')")
            continue
        article.images = images
        article.image_url = images[0].url
        await article_service.save_article(article)
        logger.info(f"Backfilled {len(images)} image(s) for {article_id}: {article.title}")
        updated += 1

    return updated


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Attach images to already-published articles.")
    parser.add_argument(
        "--all", action="store_true", dest="all_articles",
        help="Re-source every article, not just ones with no image_url.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    configure_logging(os.environ.get("LOG_LEVEL", "INFO").upper(), "scrapper", "backend", "common")
    updated = asyncio.run(backfill(all_articles=args.all_articles))
    logger.info(f"Backfilled {updated} article(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
