"""
Unit tests for reprocess_articles.py. ArticleService, WebScraper, the other pipeline
collaborators, and scheduler.run_critic_loop are all mocked -- no live network, LLM, or
Supabase calls.
"""

import logging
from datetime import date, datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from common.models import Article, ArticleImage, Citation
from scrapper.article_critic import CriticReview
import reprocess_articles


def make_article(article_id="art_20260101_001", title="Mohenjo-daro", images=()):
    return Article(
        id=article_id, title=title, summary="A summary.", content="...",
        citations=[Citation(
            text="Mohenjo-daro", source_url="https://en.wikipedia.org/wiki/Mohenjo-daro",
            source_name="wikipedia", accessed_date=datetime(2026, 1, 1, tzinfo=timezone.utc),
        )],
        images=list(images),
        publication_date=date(2026, 1, 1), reading_time_minutes=10,
    )


def make_image(index=0):
    return ArticleImage(
        url=f"https://storage.example/{index}", alt_text="a", credit="Someone via Wikimedia Commons",
        source_url="https://commons.wikimedia.org/wiki/File:X.jpg", license="CC BY-SA 4.0",
        width=1200, height=800,
    )


def _approved(article, rounds=1):
    return (article, CriticReview(approved=True, summary="ok", issues=[]), rounds)


@pytest.fixture
def services():
    with patch("reprocess_articles.ArticleService") as service_cls, \
            patch("reprocess_articles.WebScraper") as scraper_cls, \
            patch("reprocess_articles.ArticleGenerator"), \
            patch("reprocess_articles.ContentValidator"), \
            patch("reprocess_articles.ArticleCritic"), \
            patch("reprocess_articles.ImageSourcer"), \
            patch("scrapper.scheduler.run_critic_loop", new_callable=AsyncMock) as run_critic_loop:
        article = make_article()
        service = service_cls.return_value
        service.list_recent_articles = AsyncMock(side_effect=[[article], []])
        service.save_article = AsyncMock()
        scraper = scraper_cls.return_value
        scraper.search_and_scrape = AsyncMock(return_value=["scraped content"])
        run_critic_loop.return_value = _approved(article)
        yield MagicMock(service=service, scraper=scraper, run_critic_loop=run_critic_loop, article=article)


class TestReprocess:
    async def test_reprocesses_and_saves_each_article(self, services):
        updated = await reprocess_articles.reprocess()

        services.scraper.search_and_scrape.assert_awaited_once()
        services.run_critic_loop.assert_awaited_once()
        services.service.save_article.assert_awaited_once_with(services.article)
        assert updated == 1

    async def test_recovers_the_real_topic_via_the_wikipedia_citation_for_the_scrape(self, services):
        services.article.title = "Mohenjo-daro: A City Lost to Time"

        await reprocess_articles.reprocess()

        assert services.scraper.search_and_scrape.await_args.args[0] == "Mohenjo-daro"

    async def test_starts_from_the_articles_existing_images_not_a_fresh_source(self, services):
        image = make_image()
        services.article.images = [image]

        await reprocess_articles.reprocess()

        assert services.run_critic_loop.await_args.kwargs["initial_images"] == [image]

    async def test_no_scraped_content_skips_the_article(self, services):
        services.scraper.search_and_scrape.return_value = []

        updated = await reprocess_articles.reprocess()

        services.run_critic_loop.assert_not_awaited()
        services.service.save_article.assert_not_awaited()
        assert updated == 0

    async def test_a_failure_for_one_article_does_not_stop_the_batch(self, services):
        second_article = make_article("art_20260102_001", "Second")
        services.service.list_recent_articles = AsyncMock(side_effect=[
            [services.article, second_article], [],
        ])
        services.run_critic_loop.side_effect = [Exception("LLM provider down"), _approved(second_article)]

        updated = await reprocess_articles.reprocess()

        assert services.service.save_article.await_count == 1
        services.service.save_article.assert_awaited_once_with(second_article)
        assert updated == 1

    async def test_does_not_save_when_the_critic_does_not_approve_after_reprocessing(self, services):
        # A rejected round (never approved, or a revision that broke structural validity) must
        # never overwrite a working published article with a worse one.
        rejected = (services.article, CriticReview(approved=False, summary="still broken", issues=[]), 2)
        services.run_critic_loop.return_value = rejected

        updated = await reprocess_articles.reprocess()

        services.service.save_article.assert_not_awaited()
        assert updated == 0

    async def test_logs_whether_the_image_was_replaced(self, services, caplog):
        original_image = make_image(index=0)
        services.article.images = [original_image]
        replaced_article = make_article(images=[make_image(index=1)])
        services.run_critic_loop.return_value = _approved(replaced_article, rounds=2)

        with caplog.at_level(logging.INFO, logger="reprocess_articles"):
            await reprocess_articles.reprocess()

        [entry] = [r for r in caplog.records if "Reprocessed" in r.getMessage()]
        assert "image replaced" in entry.getMessage()
        assert "round 2" in entry.getMessage()

    async def test_logs_image_unchanged_when_it_was_not_replaced(self, services, caplog):
        with caplog.at_level(logging.INFO, logger="reprocess_articles"):
            await reprocess_articles.reprocess()

        [entry] = [r for r in caplog.records if "Reprocessed" in r.getMessage()]
        assert "image unchanged" in entry.getMessage()


class TestMain:
    def test_exits_zero(self):
        with patch("reprocess_articles.reprocess", new_callable=AsyncMock) as reprocess, \
                patch("reprocess_articles.configure_logging"):
            reprocess.return_value = 0
            assert reprocess_articles.main() == 0
