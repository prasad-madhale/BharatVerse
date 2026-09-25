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
from common.models import Article, ArticleImage
from scrapper.article_critic import ArticleCritic, CriticIssue, CriticReview, critic_metrics
from scrapper.article_generator import ArticleGenerator
from scrapper.content_validator import ContentValidator, article_metrics
from scrapper.image_sourcing import ImageSourcer
from scrapper.models.article import ScrapedContent
from scrapper.topic_generator import TopicGenerator
from scrapper.web_scraper import WebScraper

logger = logging.getLogger(__name__)

SOURCES = ["wikipedia", "archive_org", "new_world_encyclopedia", "indian_culture"]
MAX_GENERATION_ATTEMPTS = 3
GENERATION_BACKOFF_SECONDS = 5  # doubles after each failed attempt: 5 s, then 10 s
CRITIC_MAX_ROUNDS = 4  # up to 3 revisions per generation attempt, before falling back to a fresh attempt


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
    image_sourcer = ImageSourcer() if get_llm_settings().image_sourcing_enabled else None

    existing_titles = await article_service.list_recent_titles()
    topics = await topic_generator.generate_topics(count=count, exclude_titles=existing_titles)

    published = 0
    for i, topic in enumerate(topics, start=1):
        try:
            published += await _generate_and_publish_one(
                topic, sequence=i, scraper=scraper, generator=generator,
                validator=validator, critic=critic, image_sourcer=image_sourcer,
                article_service=article_service,
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
    image_sourcer: ImageSourcer | None,
    article_service: ArticleService,
) -> bool:
    """Returns whether the topic ended in a published article."""
    logger.info(f"Scraping '{topic}' from {SOURCES}...")
    scraped = await scraper.search_and_scrape(topic, sources=SOURCES)
    if not scraped:
        logger.warning(f"No content scraped for '{topic}', skipping")
        return False
    logger.info(f"Scraped {len(scraped)} page(s) for '{topic}'")

    article = await _generate_valid_article(
        scraped, topic, sequence, generator, validator, critic, image_sourcer
    )
    if article is None:
        logger.error(f"Giving up on '{topic}' after {MAX_GENERATION_ATTEMPTS} attempt(s)")
        return False

    await article_service.save_article(article)
    logger.info(f"Published {article.id}: {article.title} ({len(article.images)} image(s))")
    return True


async def _generate_valid_article(
    scraped: list[ScrapedContent],
    topic: str,
    sequence: int,
    generator: ArticleGenerator,
    validator: ContentValidator,
    critic: ArticleCritic | None,
    image_sourcer: ImageSourcer | None,
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
            article, review, rounds = await run_critic_loop(
                article, scraped, topic, generator, validator, critic, image_sourcer
            )
            approved = review.approved
        elif image_sourcer is not None:
            # No critic means no cohesion check to react to -- just source once, same as
            # before this pipeline could re-source on a cohesion failure.
            article.images = await _source_images(image_sourcer, article, topic)
            article.image_url = article.images[0].url if article.images else None

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


async def run_critic_loop(
    article: Article,
    scraped: list[ScrapedContent],
    topic: str,
    generator: ArticleGenerator,
    validator: ContentValidator,
    critic: ArticleCritic,
    image_sourcer: ImageSourcer | None = None,
    initial_images: list[ArticleImage] | None = None,
) -> tuple[Article, CriticReview, int]:
    """
    Up to CRITIC_MAX_ROUNDS review/revise cycles. Public (not scheduler-internal) so
    reprocess_articles.py can run existing articles through the exact same loop.

    If image_sourcer is given, images are sourced (from initial_images if provided, else
    freshly) before the first round, and every round also runs critic.review_image_cohesion
    over all of them (not just the featured image) -- a cohesion failure is folded into the
    round's issues like any other major issue, and triggers a full re-source (excluding every
    filename rejected so far), not a partial swap. A text revision that breaks structural
    validity, or that exhausts CRITIC_MAX_ROUNDS, ends the loop early (rejected).
    """
    if image_sourcer is not None:
        article.images = (
            initial_images if initial_images is not None
            else await _source_images(image_sourcer, article, topic)
        )
        article.image_url = article.images[0].url if article.images else None

    excluded_filenames: set[str] = set()
    for round_num in range(1, CRITIC_MAX_ROUNDS + 1):
        review = await critic.review(article, scraped_content=scraped, topic=topic)

        # critic.review() only judges grounding/neutrality/etc., never word count or section
        # count -- the live pipeline's caller already guarantees the article is structurally
        # valid before the first round, but a caller starting from an existing article (e.g.
        # reprocess_articles.py, re-running one published before today's word-count bar) makes
        # no such guarantee, so check it here too rather than silently approving a too-short
        # or too-long draft the critic itself has no way to catch.
        struct_valid, struct_issues = validator.validate(article)
        if not struct_valid:
            review.approved = False
            review.issues = review.issues + [CriticIssue(
                category="structure", severity="major", location="overall",
                detail=f"Fails structural validation: {'; '.join(struct_issues)}",
                suggestion="Revise to satisfy the structural requirements (word count, sections, citations).",
            )]

        image_issues: list[CriticIssue] = []
        if article.images:
            image_issues = await critic.review_image_cohesion(article, article.images)
            if image_issues:
                review.issues = review.issues + image_issues
                review.approved = False

        if review.approved or round_num == CRITIC_MAX_ROUNDS:
            return article, review, round_num

        if any(issue.category != "image_cohesion" for issue in review.issues):
            current_images = article.images
            article = await generator.revise_article(article, scraped_content=scraped, topic=topic, feedback=review)
            # revise_article rebuilds the Article from scratch and doesn't carry images over.
            article.images = current_images
            article.image_url = current_images[0].url if current_images else None
            valid, issues = validator.validate(article)
            if not valid:
                logger.warning(f"Revision of '{topic}' broke structural validity (round {round_num}): {issues}")
                return article, review, round_num

        if image_issues and image_sourcer is not None:
            excluded_filenames.update(_filenames_to_exclude(article.images, image_issues))
            article.images = await _source_images(image_sourcer, article, topic, exclude=excluded_filenames)
            article.image_url = article.images[0].url if article.images else None

    return article, review, round_num


async def _source_images(
    image_sourcer: ImageSourcer, article: Article, topic: str, exclude: set[str] = frozenset()
) -> list[ArticleImage]:
    """A sourcing failure (network error, nothing usable found) leaves the article with no
    images rather than losing an otherwise-good, critic-approved article over it."""
    try:
        return await image_sourcer.source_images(article, topic, exclude=exclude)
    except Exception:
        logger.warning(f"Image sourcing failed for '{topic}', publishing without images", exc_info=True)
        return []


def _filenames_to_exclude(images: list[ArticleImage], image_issues: list[CriticIssue]) -> set[str]:
    """Maps a review_image_cohesion issue's location ("featured image" / "inline image N")
    back to the Commons file title (the last path segment of the image's source_url, exactly
    as image_sourcing.py._host built it) so a re-source can exclude just the rejected image(s)."""
    failing_locations = {issue.location for issue in image_issues}
    filenames = set()
    for index, image in enumerate(images):
        label = "featured image" if index == 0 else f"inline image {index + 1}"
        if label in failing_locations:
            filenames.add(image.source_url.rsplit("/", 1)[-1])
    return filenames
