"""
CLI entrypoint to run already-published articles back through the current pipeline -- the
critic and image-cohesion checks a growing article may never have seen, since they only run at
generation time and several critic fixes (and the image-cohesion check itself) landed after the
first articles were published.

Usage (from the repo root or from scrapper/):
    python scrapper/reprocess_articles.py
    python reprocess_articles.py           # if already inside scrapper/

Re-scrapes using the article's own Wikipedia citation as the topic (see topic_recovery.py -- the
article's title is an LLM-written headline, not the real Wikipedia title), since scraped source
text is never persisted and the critic's grounding check needs it. Runs the exact same
run_critic_loop the daily pipeline uses, starting from the article's current images rather than
sourcing blind, so a cohesion failure replaces them the same way a freshly-generated article's
would. Idempotent per article (ArticleService.save_article overwrites), so a failed run can just
be re-run.
"""

import asyncio
import logging
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

from backend.services.article_service import ArticleService  # noqa: E402
from common.logging_config import configure_logging  # noqa: E402
from scrapper import scheduler  # noqa: E402
from scrapper.article_critic import ArticleCritic  # noqa: E402
from scrapper.article_generator import ArticleGenerator  # noqa: E402
from scrapper.content_validator import ContentValidator  # noqa: E402
from scrapper.image_sourcing import ImageSourcer  # noqa: E402
from scrapper.topic_recovery import recover_topic  # noqa: E402
from scrapper.web_scraper import WebScraper  # noqa: E402

# Not logging.getLogger(__name__): running this file directly (`python3 reprocess_articles.py`)
# makes __name__ "__main__", which wouldn't match the "reprocess_articles" name configure_logging
# is given below, silently dropping every INFO-level log (only WARNING+ would show, unformatted,
# via Python's logging.lastResort). A hardcoded name matches in both that case and when pytest
# imports this file as a module named "reprocess_articles".
logger = logging.getLogger("reprocess_articles")


async def reprocess() -> int:
    """Returns how many articles were successfully reprocessed and saved."""
    article_service = ArticleService()
    scraper = WebScraper()
    generator = ArticleGenerator()
    validator = ContentValidator()
    critic = ArticleCritic()
    image_sourcer = ImageSourcer()

    articles = []
    offset = 0
    while batch := await article_service.list_recent_articles(limit=100, offset=offset):
        articles.extend(batch)
        offset += 100

    logger.info(f"Reprocessing {len(articles)} article(s)")
    updated = 0
    for article in articles:
        topic = recover_topic(article)
        try:
            scraped = await scraper.search_and_scrape(topic, sources=scheduler.SOURCES)
            if not scraped:
                logger.warning(f"No content scraped for {article.id} ('{topic}'), skipping")
                continue

            original_image_urls = [image.url for image in article.images]
            reprocessed, review, rounds = await scheduler.run_critic_loop(
                article, scraped, topic, generator, validator, critic,
                image_sourcer=image_sourcer,
                # An empty list here (a pre-image-era article, or one left imageless by a
                # previous save that failed partway through -- see ArticleService.save_article's
                # non-atomic content-then-row write) must source fresh, not be taken as "this
                # article intentionally has no images, leave it that way".
                initial_images=article.images or None,
            )
        except Exception:
            logger.warning(f"Reprocessing failed for {article.id} ('{topic}')", exc_info=True)
            continue

        if not review.approved:
            # The already-published article is left untouched -- a rejected round (the critic
            # never approved, or a revision broke structural validity) must never overwrite a
            # working article with a worse one.
            logger.warning(
                f"{article.id} not approved after reprocessing (round {rounds}): {review.summary} "
                f"-- leaving the published article unchanged"
            )
            continue

        try:
            await article_service.save_article(reprocessed)
        except Exception:
            # An approved reprocess that fails to save (a transient network error, or a schema
            # mismatch like a column PostgREST's cache doesn't know about yet) must not abort
            # the rest of the batch -- the published article is simply left as it was, same as
            # a rejected review above.
            logger.warning(f"Saving reprocessed {article.id} failed -- leaving it unchanged", exc_info=True)
            continue
        image_changed = [image.url for image in reprocessed.images] != original_image_urls
        logger.info(
            f"Reprocessed {reprocessed.id}: {reprocessed.title} "
            f"(round {rounds}, approved, image {'replaced' if image_changed else 'unchanged'})"
        )
        updated += 1

    return updated


def main() -> int:
    configure_logging(os.environ.get("LOG_LEVEL", "INFO").upper(), "reprocess_articles", "scrapper", "backend", "common")
    updated = asyncio.run(reprocess())
    logger.info(f"Reprocessed {updated} article(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
