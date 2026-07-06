"""
Daily pipeline orchestrator: AI topic selection -> multi-source scrape ->
LLM article generation -> automated validation -> Supabase persistence.

Replaces Phase 0's hardcoded-topic runner (see .kiro/specs/bharatverse-mvp/
roadmap.md, Phase 4). Human-in-the-loop review is explicitly deferred;
ContentValidator's automated checks stand in for it for now.
"""

import logging

from backend.services.article_service import ArticleService
from scrapper.article_generator import ArticleGenerator
from scrapper.content_validator import ContentValidator
from scrapper.topic_generator import TopicGenerator
from scrapper.web_scraper import WebScraper

logger = logging.getLogger(__name__)

SOURCES = ["wikipedia", "archive_org", "new_world_encyclopedia"]


async def run_daily_pipeline(count: int = 1) -> None:
    """
    Generate and publish `count` new article(s), each on a topic not
    already covered by an existing article.
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

    article = await generator.generate_article(scraped, topic=topic, sequence=sequence)
    valid, issues = validator.validate(article)

    if not valid:
        logger.warning(f"Validation failed for '{topic}': {issues}. Retrying generation once.")
        article = await generator.generate_article(scraped, topic=topic, sequence=sequence)
        valid, issues = validator.validate(article)
        if not valid:
            logger.error(f"Still invalid after retry, skipping '{topic}': {issues}")
            return

    await article_service.save_article(article)
    logger.info(f"Published {article.id}: {article.title}")
