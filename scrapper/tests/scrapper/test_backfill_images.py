"""
Unit tests for backfill_images.py. ArticleService and ImageSourcer are mocked -- no live
network or Supabase calls.
"""

from datetime import date
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from common.models import Article, ArticleImage
from scrapper import backfill_images


def make_article(article_id="art_20260101_001", title="Mohenjo-daro"):
    return Article(
        id=article_id, title=title, summary="A summary.", content="...",
        publication_date=date(2026, 1, 1), reading_time_minutes=10,
    )


def make_image(index=0):
    return ArticleImage(
        url=f"https://storage.example/{index}", alt_text="a", credit="Someone via Wikimedia Commons",
        source_url="https://commons.wikimedia.org/wiki/File:X.jpg", license="CC BY-SA 4.0",
    )


@pytest.fixture
def services():
    with patch("scrapper.backfill_images.ArticleService") as service_cls, \
            patch("scrapper.backfill_images.ImageSourcer") as sourcer_cls:
        service = service_cls.return_value
        service.list_ids_missing_images = AsyncMock(return_value=["art_20260101_001"])
        service.get_article_by_id = AsyncMock(return_value=make_article())
        service.save_article = AsyncMock()
        sourcer = sourcer_cls.return_value
        sourcer.source_images = AsyncMock(return_value=[make_image()])
        yield MagicMock(service=service, sourcer=sourcer)


class TestBackfill:
    async def test_attaches_images_and_saves_only_articles_missing_them(self, services):
        updated = await backfill_images.backfill()

        services.service.list_ids_missing_images.assert_awaited_once()
        services.service.save_article.assert_awaited_once()
        saved_article = services.service.save_article.await_args.args[0]
        assert saved_article.images[0].url == "https://storage.example/0"
        assert saved_article.image_url == "https://storage.example/0"
        assert updated == 1

    async def test_all_flag_paginates_through_every_article_instead(self, services):
        page_one = [make_article(f"art_{n}") for n in range(100)]
        services.service.list_recent_articles = AsyncMock(side_effect=[page_one, []])

        await backfill_images.backfill(all_articles=True)

        services.service.list_ids_missing_images.assert_not_awaited()
        assert services.service.get_article_by_id.await_count == 100

    async def test_an_article_that_disappears_is_skipped_not_a_crash(self, services):
        services.service.get_article_by_id.return_value = None

        updated = await backfill_images.backfill()

        services.service.save_article.assert_not_awaited()
        assert updated == 0

    async def test_a_sourcing_failure_for_one_article_does_not_stop_the_batch(self, services):
        services.service.list_ids_missing_images.return_value = ["art_1", "art_2"]
        services.service.get_article_by_id.side_effect = [make_article("art_1"), make_article("art_2")]
        services.sourcer.source_images.side_effect = [Exception("boom"), [make_image()]]

        updated = await backfill_images.backfill()

        assert services.service.save_article.await_count == 1
        assert updated == 1

    async def test_no_images_found_is_not_saved_or_counted(self, services):
        services.sourcer.source_images.return_value = []

        updated = await backfill_images.backfill()

        services.service.save_article.assert_not_awaited()
        assert updated == 0


class TestMain:
    def test_all_flag_is_passed_through(self):
        with patch("scrapper.backfill_images.backfill", new_callable=AsyncMock) as backfill, \
                patch("scrapper.backfill_images.configure_logging"):
            backfill.return_value = 0
            backfill_images.main(["--all"])

        assert backfill.await_args.kwargs == {"all_articles": True}

    def test_exits_zero_even_when_nothing_was_updated(self):
        with patch("scrapper.backfill_images.backfill", new_callable=AsyncMock) as backfill, \
                patch("scrapper.backfill_images.configure_logging"):
            backfill.return_value = 0
            assert backfill_images.main([]) == 0
