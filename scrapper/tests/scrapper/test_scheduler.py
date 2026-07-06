"""
Unit tests for the daily pipeline orchestrator (scrapper.scheduler).

All collaborators (ArticleService, TopicGenerator, WebScraper,
ArticleGenerator, ContentValidator) are mocked -- this tests the
orchestration logic only, not any real scraping/LLM/Supabase behavior
(those are covered by each collaborator's own tests).
"""

from unittest.mock import AsyncMock, MagicMock, patch

from scrapper import scheduler


def _make_article(article_id="art_20260705_001", title="Some Article"):
    article = MagicMock()
    article.id = article_id
    article.title = title
    return article


class TestRunDailyPipeline:
    @patch("scrapper.scheduler.ArticleService")
    @patch("scrapper.scheduler.TopicGenerator")
    @patch("scrapper.scheduler.WebScraper")
    @patch("scrapper.scheduler.ArticleGenerator")
    @patch("scrapper.scheduler.ContentValidator")
    async def test_happy_path_generates_and_publishes_one_article(
        self, mock_validator_cls, mock_generator_cls, mock_scraper_cls,
        mock_topic_gen_cls, mock_service_cls,
    ):
        mock_service = mock_service_cls.return_value
        mock_service.list_recent_titles = AsyncMock(return_value=["Old Topic"])
        mock_service.save_article = AsyncMock()

        mock_topic_gen = mock_topic_gen_cls.return_value
        mock_topic_gen.generate_topics = AsyncMock(return_value=["New Topic"])

        mock_scraper = mock_scraper_cls.return_value
        mock_scraper.search_and_scrape = AsyncMock(return_value=["scraped content"])

        article = _make_article()
        mock_generator = mock_generator_cls.return_value
        mock_generator.generate_article = AsyncMock(return_value=article)

        mock_validator = mock_validator_cls.return_value
        mock_validator.validate.return_value = (True, [])

        await scheduler.run_daily_pipeline(count=1)

        mock_topic_gen.generate_topics.assert_awaited_once_with(count=1, exclude_titles=["Old Topic"])
        mock_scraper.search_and_scrape.assert_awaited_once_with("New Topic", sources=scheduler.SOURCES)
        mock_generator.generate_article.assert_awaited_once_with(
            ["scraped content"], topic="New Topic", sequence=1
        )
        mock_service.save_article.assert_awaited_once_with(article)

    @patch("scrapper.scheduler.ArticleService")
    @patch("scrapper.scheduler.TopicGenerator")
    @patch("scrapper.scheduler.WebScraper")
    @patch("scrapper.scheduler.ArticleGenerator")
    @patch("scrapper.scheduler.ContentValidator")
    async def test_multiple_topics_get_sequential_sequence_numbers(
        self, mock_validator_cls, mock_generator_cls, mock_scraper_cls,
        mock_topic_gen_cls, mock_service_cls,
    ):
        mock_service = mock_service_cls.return_value
        mock_service.list_recent_titles = AsyncMock(return_value=[])
        mock_service.save_article = AsyncMock()

        mock_topic_gen = mock_topic_gen_cls.return_value
        mock_topic_gen.generate_topics = AsyncMock(return_value=["Topic A", "Topic B"])

        mock_scraper = mock_scraper_cls.return_value
        mock_scraper.search_and_scrape = AsyncMock(return_value=["scraped content"])

        mock_generator = mock_generator_cls.return_value
        mock_generator.generate_article = AsyncMock(side_effect=[_make_article("art_1"), _make_article("art_2")])

        mock_validator = mock_validator_cls.return_value
        mock_validator.validate.return_value = (True, [])

        await scheduler.run_daily_pipeline(count=2)

        assert mock_generator.generate_article.await_args_list[0].kwargs["sequence"] == 1
        assert mock_generator.generate_article.await_args_list[1].kwargs["sequence"] == 2
        assert mock_service.save_article.await_count == 2

    @patch("scrapper.scheduler.ArticleService")
    @patch("scrapper.scheduler.TopicGenerator")
    @patch("scrapper.scheduler.WebScraper")
    @patch("scrapper.scheduler.ArticleGenerator")
    @patch("scrapper.scheduler.ContentValidator")
    async def test_skips_topic_with_no_scraped_content(
        self, mock_validator_cls, mock_generator_cls, mock_scraper_cls,
        mock_topic_gen_cls, mock_service_cls,
    ):
        mock_service = mock_service_cls.return_value
        mock_service.list_recent_titles = AsyncMock(return_value=[])
        mock_service.save_article = AsyncMock()

        mock_topic_gen = mock_topic_gen_cls.return_value
        mock_topic_gen.generate_topics = AsyncMock(return_value=["Unscrapable Topic"])

        mock_scraper = mock_scraper_cls.return_value
        mock_scraper.search_and_scrape = AsyncMock(return_value=[])

        mock_generator = mock_generator_cls.return_value
        mock_generator.generate_article = AsyncMock()

        await scheduler.run_daily_pipeline(count=1)

        mock_generator.generate_article.assert_not_awaited()
        mock_service.save_article.assert_not_awaited()

    @patch("scrapper.scheduler.ArticleService")
    @patch("scrapper.scheduler.TopicGenerator")
    @patch("scrapper.scheduler.WebScraper")
    @patch("scrapper.scheduler.ArticleGenerator")
    @patch("scrapper.scheduler.ContentValidator")
    async def test_retries_once_on_validation_failure_then_publishes(
        self, mock_validator_cls, mock_generator_cls, mock_scraper_cls,
        mock_topic_gen_cls, mock_service_cls,
    ):
        mock_service = mock_service_cls.return_value
        mock_service.list_recent_titles = AsyncMock(return_value=[])
        mock_service.save_article = AsyncMock()

        mock_topic_gen = mock_topic_gen_cls.return_value
        mock_topic_gen.generate_topics = AsyncMock(return_value=["Flaky Topic"])

        mock_scraper = mock_scraper_cls.return_value
        mock_scraper.search_and_scrape = AsyncMock(return_value=["scraped content"])

        first_attempt = _make_article("art_bad")
        second_attempt = _make_article("art_good")
        mock_generator = mock_generator_cls.return_value
        mock_generator.generate_article = AsyncMock(side_effect=[first_attempt, second_attempt])

        mock_validator = mock_validator_cls.return_value
        mock_validator.validate.side_effect = [(False, ["too short"]), (True, [])]

        await scheduler.run_daily_pipeline(count=1)

        assert mock_generator.generate_article.await_count == 2
        mock_service.save_article.assert_awaited_once_with(second_attempt)

    @patch("scrapper.scheduler.ArticleService")
    @patch("scrapper.scheduler.TopicGenerator")
    @patch("scrapper.scheduler.WebScraper")
    @patch("scrapper.scheduler.ArticleGenerator")
    @patch("scrapper.scheduler.ContentValidator")
    async def test_skips_topic_when_still_invalid_after_retry(
        self, mock_validator_cls, mock_generator_cls, mock_scraper_cls,
        mock_topic_gen_cls, mock_service_cls,
    ):
        mock_service = mock_service_cls.return_value
        mock_service.list_recent_titles = AsyncMock(return_value=[])
        mock_service.save_article = AsyncMock()

        mock_topic_gen = mock_topic_gen_cls.return_value
        mock_topic_gen.generate_topics = AsyncMock(return_value=["Persistently Bad Topic"])

        mock_scraper = mock_scraper_cls.return_value
        mock_scraper.search_and_scrape = AsyncMock(return_value=["scraped content"])

        mock_generator = mock_generator_cls.return_value
        mock_generator.generate_article = AsyncMock(
            side_effect=[_make_article("art_bad1"), _make_article("art_bad2")]
        )

        mock_validator = mock_validator_cls.return_value
        mock_validator.validate.side_effect = [(False, ["too short"]), (False, ["still too short"])]

        await scheduler.run_daily_pipeline(count=1)

        assert mock_generator.generate_article.await_count == 2
        mock_service.save_article.assert_not_awaited()
