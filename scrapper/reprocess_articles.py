"""
CLI entrypoint to run already-published articles back through the current pipeline -- the
critic and image-cohesion checks a growing article may never have seen, since they only run at
generation time and several critic fixes (and the image-cohesion check itself) landed after the
first articles were published.

Usage (from the repo root or from scrapper/):
    python scrapper/reprocess_articles.py
    python scrapper/reprocess_articles.py --ids art_20260705_001 art_20260709_001   # only these articles
    python scrapper/reprocess_articles.py --eras-only    # only give an era to articles without a listed one
    python reprocess_articles.py           # if already inside scrapper/

Re-scrapes using the article's own Wikipedia citation as the topic (see topic_recovery.py -- the
article's title is an LLM-written headline, not the real Wikipedia title), since scraped source
text is never persisted and the critic's grounding check needs it. Runs the exact same
run_critic_loop the daily pipeline uses, starting from the article's current images rather than
sourcing blind, so a cohesion failure replaces them the same way a freshly-generated article's
would. Idempotent per article (ArticleService.save_article overwrites), so a failed run can just
be re-run.

--eras-only skips all of that: one short LLM call per article picks its era from common.eras, judged
from its title and summary, for articles published before the era list.
"""

import argparse
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
from common.eras import ERAS  # noqa: E402
from common.logging_config import configure_logging  # noqa: E402
from common.models import Article  # noqa: E402
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


async def _load_articles(article_service: ArticleService, ids: list[str] | None) -> list[Article]:
    """The articles named by `ids`, or every article when it is None."""
    if ids is not None:
        articles = []
        for article_id in ids:
            article = await article_service.get_article_by_id(article_id)
            if article is None:
                logger.warning(f"No article {article_id}, skipping")
            else:
                articles.append(article)
        return articles

    articles = []
    offset = 0
    while batch := await article_service.list_recent_articles(limit=100, offset=offset):
        articles.extend(batch)
        offset += 100
    return articles


async def assign_eras(ids: list[str] | None = None) -> int:
    """Gives every article whose era is not on the list one; returns how many were saved."""
    article_service = ArticleService()
    generator = ArticleGenerator()

    articles = await _load_articles(article_service, ids)
    logger.info(f"Checking the era of {len(articles)} article(s)")
    updated = 0
    for article in articles:
        if article.era in ERAS:
            logger.info(f"{article.id} already has a listed era: {article.era}")
            continue
        try:
            era = await generator.choose_era(article)
        except Exception:
            logger.warning(f"Choosing an era failed for {article.id} ('{article.title}')", exc_info=True)
            continue

        previous = article.era
        article.era = era
        try:
            await article_service.save_article(article)
        except Exception:
            logger.warning(f"Saving the era of {article.id} failed -- leaving it unchanged", exc_info=True)
            continue
        logger.info(f"{article.id}: era '{previous}' -> '{era}' ({article.title})")
        updated += 1

    return updated


async def reprocess(ids: list[str] | None = None) -> int:
    """Returns how many articles were successfully reprocessed and saved."""
    article_service = ArticleService()
    scraper = WebScraper()
    generator = ArticleGenerator()
    validator = ContentValidator()
    critic = ArticleCritic()
    image_sourcer = ImageSourcer()

    articles = await _load_articles(article_service, ids)

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
                # An empty list here (a pre-image-era article, or one left imageless by a save
                # that failed part way before save_article became crash-safe) must source fresh,
                # not be taken as "this article intentionally has no images, leave it that way".
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


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run published articles back through the current pipeline.")
    parser.add_argument("--ids", nargs="+", metavar="ID", help="Only these articles (default: every article).")
    parser.add_argument(
        "--eras-only", action="store_true",
        help="Only give an era from the list to articles that lack one: one short LLM call each, no re-scrape.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    configure_logging(os.environ.get("LOG_LEVEL", "INFO").upper(), "reprocess_articles", "scrapper", "backend", "common")
    if args.eras_only:
        logger.info(f"Gave an era to {asyncio.run(assign_eras(args.ids))} article(s)")
        return 0
    updated = asyncio.run(reprocess(args.ids))
    logger.info(f"Reprocessed {updated} article(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
