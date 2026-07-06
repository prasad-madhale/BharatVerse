"""
Daily pipeline orchestrator: AI topic selection -> multi-source scrape ->
LLM article generation -> automated validation -> Supabase persistence.

Replaces Phase 0's hardcoded-topic runner (see .kiro/specs/bharatverse-mvp/
roadmap.md, Phase 4). Human-in-the-loop review is explicitly deferred;
ContentValidator's automated checks stand in for it for now.
"""

import logging

from backend.services.article_service import ArticleService
from common.models import Article
from scrapper.article_generator import ArticleGenerationError, ArticleGenerator
from scrapper.content_validator import ContentValidator
from scrapper.models.article import ScrapedContent
from scrapper.topic_generator import TopicGenerator
from scrapper.web_scraper import WebScraper

logger = logging.getLogger(__name__)

SOURCES = ["wikipedia", "archive_org", "new_world_encyclopedia"]
MAX_GENERATION_ATTEMPTS = 2


async def run_daily_pipeline(count: int = 1) -> None:
    """
    Generate and publish `count` new article(s), each on a topic not
    already covered by an existing article.

    A single topic failing (unscrapable, or generation/validation failing
    twice) is logged and skipped -- it never aborts the rest of the batch.
    """
    article_service = ArticleService()
    topic_generator = TopicGenerator()
    scraper = WebScraper()
    generator = ArticleGenerator()
    validator = ContentValidator()

    existing_titles = await article_service.list_recent_titles()
    topics = await topic_generator.generate_topics(count=count, exclude_titles=existing_titles)

    for i, topic in enumerate(topics, start=1):
        await _generate_and_publish_one(
            topic, sequence=i, scraper=scraper, generator=generator,
            validator=validator, article_service=article_service,
        )


async def _generate_and_publish_one(
    topic: str,
    sequence: int,
    scraper: WebScraper,
    generator: ArticleGenerator,
    validator: ContentValidator,
    article_service: ArticleService,
) -> None:
    logger.info(f"Scraping '{topic}' from {SOURCES}...")
    scraped = await scraper.search_and_scrape(topic, sources=SOURCES)
    if not scraped:
        logger.warning(f"No content scraped for '{topic}', skipping")
        return
    logger.info(f"Scraped {len(scraped)} page(s) for '{topic}'")

    article = await _generate_valid_article(scraped, topic, sequence, generator, validator)
    if article is None:
        logger.error(f"Giving up on '{topic}' after {MAX_GENERATION_ATTEMPTS} attempt(s)")
        return

    await article_service.save_article(article)
    logger.info(f"Published {article.id}: {article.title}")


async def _generate_valid_article(
    scraped: list[ScrapedContent],
    topic: str,
    sequence: int,
    generator: ArticleGenerator,
    validator: ContentValidator,
) -> Article | None:
    """
    Generate an article and validate it, retrying up to MAX_GENERATION_ATTEMPTS
    times on either a generation failure (e.g. unparseable LLM output) or a
    content-validation failure. Returns None if every attempt fails.
    """
    for attempt in range(1, MAX_GENERATION_ATTEMPTS + 1):
        try:
            article = await generator.generate_article(scraped, topic=topic, sequence=sequence)
        except ArticleGenerationError as e:
            logger.warning(f"Generation failed for '{topic}' (attempt {attempt}): {e}")
            continue

        valid, issues = validator.validate(article)
        if valid:
            return article
        logger.warning(f"Validation failed for '{topic}' (attempt {attempt}): {issues}")

    return None
