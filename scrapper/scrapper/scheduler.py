"""
Daily pipeline orchestrator: AI topic selection -> multi-source scrape ->
LLM article generation -> automated validation -> Supabase persistence.

Replaces Phase 0's hardcoded-topic runner (see .kiro/specs/bharatverse-mvp/
roadmap.md, Phase 4). Human-in-the-loop review is explicitly deferred;
ContentValidator's automated checks stand in for it for now.
"""

import logging
from asyncio import sleep
from time import perf_counter

from backend.services.article_service import ArticleService
from common.models import Article
from scrapper.article_generator import ArticleGenerator
from scrapper.content_validator import ContentValidator, article_metrics
from scrapper.models.article import ScrapedContent
from scrapper.topic_generator import TopicGenerator
from scrapper.web_scraper import WebScraper

logger = logging.getLogger(__name__)

SOURCES = ["wikipedia", "archive_org", "new_world_encyclopedia"]
MAX_GENERATION_ATTEMPTS = 3
GENERATION_BACKOFF_SECONDS = 5  # doubles after each failed attempt: 5 s, then 10 s


async def run_daily_pipeline(count: int = 1) -> int:
    """
    Generate and publish `count` new article(s), each on a topic not
    already covered by an existing article. Returns how many were published.

    A single topic failing (unscrapable, generation or validation failing on
    every attempt, or anything else going wrong) is logged with its traceback
    and skipped -- it never aborts the rest of the batch.
    """
    article_service = ArticleService()
    topic_generator = TopicGenerator()
    scraper = WebScraper()
    generator = ArticleGenerator()
    validator = ContentValidator()

    existing_titles = await article_service.list_recent_titles()
    topics = await topic_generator.generate_topics(count=count, exclude_titles=existing_titles)

    published = 0
    for i, topic in enumerate(topics, start=1):
        try:
            published += await _generate_and_publish_one(
                topic, sequence=i, scraper=scraper, generator=generator,
                validator=validator, article_service=article_service,
            )
        except Exception:
            logger.exception(f"Unexpected error on '{topic}', skipping")
    return published


async def _generate_and_publish_one(
    topic: str,
    sequence: int,
    scraper: WebScraper,
    generator: ArticleGenerator,
    validator: ContentValidator,
    article_service: ArticleService,
) -> bool:
    """Returns whether the topic ended in a published article."""
    logger.info(f"Scraping '{topic}' from {SOURCES}...")
    scraped = await scraper.search_and_scrape(topic, sources=SOURCES)
    if not scraped:
        logger.warning(f"No content scraped for '{topic}', skipping")
        return False
    logger.info(f"Scraped {len(scraped)} page(s) for '{topic}'")

    article = await _generate_valid_article(scraped, topic, sequence, generator, validator)
    if article is None:
        logger.error(f"Giving up on '{topic}' after {MAX_GENERATION_ATTEMPTS} attempt(s)")
        return False

    await article_service.save_article(article)
    logger.info(f"Published {article.id}: {article.title}")
    return True


async def _generate_valid_article(
    scraped: list[ScrapedContent],
    topic: str,
    sequence: int,
    generator: ArticleGenerator,
    validator: ContentValidator,
) -> Article | None:
    """
    Generate an article and validate it, trying up to MAX_GENERATION_ATTEMPTS
    times. A generation failure (unusable LLM output, or the provider itself
    failing, say a rate limit) waits with exponential backoff before the next
    attempt; a validation failure retries at once, since the output was
    delivered and the next draw may simply be better. The quality metrics of
    every article generated, accepted or not, are logged. Returns None if
    every attempt fails.
    """
    for attempt in range(1, MAX_GENERATION_ATTEMPTS + 1):
        started = perf_counter()
        try:
            article = await generator.generate_article(scraped, topic=topic, sequence=sequence)
        except Exception as e:
            logger.warning(
                f"Generation failed for '{topic}' (attempt {attempt} of {MAX_GENERATION_ATTEMPTS}): {e}",
                exc_info=True,
            )
            if attempt < MAX_GENERATION_ATTEMPTS:
                await sleep(GENERATION_BACKOFF_SECONDS * 2 ** (attempt - 1))
            continue

        valid, issues = validator.validate(article)
        measured = {
            "topic": topic, "attempt": attempt, "valid": valid, **article_metrics(article),
            "generation_seconds": round(perf_counter() - started, 1),
        }
        if valid:
            logger.info(f"Generated '{topic}' (attempt {attempt}): {measured['word_count']} words", extra=measured)
            return article
        logger.warning(f"Validation failed for '{topic}' (attempt {attempt}): {issues}", extra=measured)

    return None
