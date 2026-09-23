"""
Daily pipeline orchestrator: AI topic selection -> multi-source scrape ->
LLM article generation -> automated validation -> editorial critic review ->
Supabase persistence.

Replaces Phase 0's hardcoded-topic runner (see docs/roadmap.md, Phase 4).
Human-in-the-loop review is explicitly deferred; ContentValidator's structural
checks and ArticleCritic's editorial review stand in for it for now.
"""

import logging
from asyncio import sleep
from time import perf_counter

from backend.services.article_service import ArticleService
from common.config import get_llm_settings
from common.models import Article
from scrapper.article_critic import ArticleCritic, CriticReview, critic_metrics
from scrapper.article_generator import ArticleGenerator
from scrapper.content_validator import ContentValidator, article_metrics
from scrapper.models.article import ScrapedContent
from scrapper.topic_generator import TopicGenerator
from scrapper.web_scraper import WebScraper

logger = logging.getLogger(__name__)

SOURCES = ["wikipedia", "archive_org", "new_world_encyclopedia", "indian_culture"]
MAX_GENERATION_ATTEMPTS = 3
GENERATION_BACKOFF_SECONDS = 5  # doubles after each failed attempt: 5 s, then 10 s
CRITIC_MAX_ROUNDS = 2  # review/revise cycles per generation attempt, before falling back to a fresh attempt


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
    critic = ArticleCritic() if get_llm_settings().critic_enabled else None

    existing_titles = await article_service.list_recent_titles()
    topics = await topic_generator.generate_topics(count=count, exclude_titles=existing_titles)

    published = 0
    for i, topic in enumerate(topics, start=1):
        try:
            published += await _generate_and_publish_one(
                topic, sequence=i, scraper=scraper, generator=generator,
                validator=validator, critic=critic, article_service=article_service,
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
    critic: ArticleCritic | None,
    article_service: ArticleService,
) -> bool:
    """Returns whether the topic ended in a published article."""
    logger.info(f"Scraping '{topic}' from {SOURCES}...")
    scraped = await scraper.search_and_scrape(topic, sources=SOURCES)
    if not scraped:
        logger.warning(f"No content scraped for '{topic}', skipping")
        return False
    logger.info(f"Scraped {len(scraped)} page(s) for '{topic}'")

    article = await _generate_valid_article(scraped, topic, sequence, generator, validator, critic)
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
    critic: ArticleCritic | None,
) -> Article | None:
    """
    Generate an article, validate it, and (if a critic is configured) have it
    reviewed and revised until the critic approves, trying up to
    MAX_GENERATION_ATTEMPTS times. A generation failure (unusable LLM output,
    or the provider itself failing, say a rate limit) waits with exponential
    backoff before the next attempt; a validation or critic failure retries
    at once with a fresh generation, since the output was delivered and the
    next draw may simply be better. The quality metrics of every article
    generated, accepted or not, are logged. Returns None if every attempt
    fails.
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
        if not valid:
            measured = {
                "topic": topic, "attempt": attempt, "valid": False, **article_metrics(article),
                "generation_seconds": round(perf_counter() - started, 1),
            }
            logger.warning(f"Validation failed for '{topic}' (attempt {attempt}): {issues}", extra=measured)
            continue

        review: CriticReview | None = None
        rounds = 0
        approved = True
        if critic is not None:
            article, review, rounds = await _run_critic_loop(article, scraped, topic, generator, validator, critic)
            approved = review.approved

        measured = {
            "topic": topic, "attempt": attempt, "valid": approved, **article_metrics(article),
            "generation_seconds": round(perf_counter() - started, 1),
        }
        if review is not None:
            measured.update(critic_metrics(review, rounds))

        if approved:
            logger.info(f"Generated '{topic}' (attempt {attempt}): {measured['word_count']} words", extra=measured)
            return article
        logger.warning(
            f"Critic did not approve '{topic}' after {rounds} round(s) (attempt {attempt}): {review.summary}",
            extra=measured,
        )

    return None


async def _run_critic_loop(
    article: Article,
    scraped: list[ScrapedContent],
    topic: str,
    generator: ArticleGenerator,
    validator: ContentValidator,
    critic: ArticleCritic,
) -> tuple[Article, CriticReview, int]:
    """
    Up to CRITIC_MAX_ROUNDS review/revise cycles. A revision that breaks
    structural validity ends the loop early (rejected) rather than spending
    remaining rounds critiquing an already-broken draft.
    """
    for round_num in range(1, CRITIC_MAX_ROUNDS + 1):
        review = await critic.review(article, scraped_content=scraped, topic=topic)
        if review.approved or round_num == CRITIC_MAX_ROUNDS:
            return article, review, round_num
        article = await generator.revise_article(article, scraped_content=scraped, topic=topic, feedback=review)
        valid, issues = validator.validate(article)
        if not valid:
            logger.warning(f"Revision of '{topic}' broke structural validity (round {round_num}): {issues}")
            return article, review, round_num
