"""
Unit tests for WebScraper.

Tests scraper logic with mocked sources and rate limiter.
"""

import pytest
import requests
from unittest.mock import MagicMock, AsyncMock, patch
from scrapper.user_agent import USER_AGENT
from scrapper.web_scraper import WebScraper
from scrapper.models.article import ScrapedContent
from datetime import datetime, timezone


class TestWebScraperInitialization:
    """Test WebScraper initialization."""

    def test_scraper_initialization_default(self):
        """Test WebScraper initializes with default rate limit."""
        scraper = WebScraper()

        assert scraper.registry is not None
        assert scraper.rate_limiter is not None
        assert scraper.rate_limiter.min_interval == 2.0  # 1/0.5 = 2 seconds
        assert scraper._robots_cache == {}

    def test_scraper_initialization_custom_rate(self):
        """Test WebScraper initializes with custom rate limit."""
        scraper = WebScraper(requests_per_second=2.0)

        assert scraper.rate_limiter.min_interval == 0.5  # 1/2 = 0.5 seconds

    def test_list_sources(self):
        """Test list_sources() returns available sources."""
        scraper = WebScraper()
        sources = scraper.list_sources()

        assert isinstance(sources, list)
        # Should have at least wikipedia and archive_org
        assert len(sources) >= 2


def _robots_response(status_code=200, text=""):
    response = MagicMock()
    response.status_code = status_code
    response.text = text
    return response


class TestWebScraperRobotsTxt:
    """robots.txt (requirement 1.5), against stubbed responses."""

    @pytest.mark.asyncio
    async def test_allows_and_disallows_by_path(self):
        scraper = WebScraper()
        robots = "User-agent: *\nDisallow: /admin\n"

        with patch('scrapper.web_scraper.requests.get', return_value=_robots_response(text=robots)):
            assert await scraper.check_robots_txt("https://example.com/page") is True
            assert await scraper.check_robots_txt("https://example.com/admin/users") is False

    @pytest.mark.asyncio
    async def test_fetches_robots_txt_with_our_user_agent(self):
        """Wikipedia answers Python's default agent with 403, which reads as "disallow everything"."""
        scraper = WebScraper()

        with patch('scrapper.web_scraper.requests.get', return_value=_robots_response()) as get:
            await scraper.check_robots_txt("https://en.wikipedia.org/wiki/Ashoka")

        get.assert_called_once()
        assert get.call_args.args == ("https://en.wikipedia.org/robots.txt",)
        assert get.call_args.kwargs["headers"] == {"User-Agent": USER_AGENT}

    @pytest.mark.asyncio
    async def test_applies_the_rules_for_our_agent(self):
        scraper = WebScraper()
        robots = "User-agent: BharatVerse\nDisallow: /\n\nUser-agent: *\nAllow: /\n"

        with patch('scrapper.web_scraper.requests.get', return_value=_robots_response(text=robots)):
            assert await scraper.check_robots_txt("https://example.com/page") is False
            assert await scraper.check_robots_txt("https://example.com/page", user_agent="OtherBot/1.0") is True

    @pytest.mark.asyncio
    async def test_fetches_each_sites_robots_txt_once(self):
        scraper = WebScraper()

        with patch('scrapper.web_scraper.requests.get', return_value=_robots_response()) as get:
            await scraper.check_robots_txt("https://example.com/page1")
            await scraper.check_robots_txt("https://example.com/page2")
            await scraper.check_robots_txt("https://other.org/page")

        assert [c.args[0] for c in get.call_args_list] == [
            "https://example.com/robots.txt", "https://other.org/robots.txt"]

    @pytest.mark.asyncio
    @pytest.mark.parametrize("status_code", [401, 403])
    async def test_a_refused_robots_txt_allows_nothing(self, status_code):
        scraper = WebScraper()

        with patch('scrapper.web_scraper.requests.get', return_value=_robots_response(status_code)):
            assert await scraper.check_robots_txt("https://example.com/page") is False

    @pytest.mark.asyncio
    async def test_a_missing_robots_txt_allows_everything(self):
        scraper = WebScraper()

        with patch('scrapper.web_scraper.requests.get', return_value=_robots_response(404, "<html>Not found")):
            assert await scraper.check_robots_txt("https://example.com/page") is True

    @pytest.mark.asyncio
    async def test_a_server_error_allows_nothing_until_it_can_be_read(self):
        """RFC 9309: a robots.txt that cannot be read for a server error means "disallow" for now."""
        scraper = WebScraper()

        with patch('scrapper.web_scraper.requests.get', return_value=_robots_response(503)):
            assert await scraper.check_robots_txt("https://example.com/page") is False
        with patch('scrapper.web_scraper.requests.get', return_value=_robots_response()) as get:
            assert await scraper.check_robots_txt("https://example.com/page") is True

        get.assert_called_once()

    @pytest.mark.asyncio
    async def test_an_unreachable_robots_txt_allows_nothing(self):
        scraper = WebScraper()

        with patch('scrapper.web_scraper.requests.get', side_effect=requests.ConnectionError("no route")):
            assert await scraper.check_robots_txt("https://example.com/page") is False

        assert scraper._robots_cache == {}


class TestWebScraperScrape:
    """Test scrape() method."""

    @pytest.mark.asyncio
    async def test_scrape_source_not_found(self):
        """Test scrape() raises ValueError for unknown source."""
        scraper = WebScraper()

        with pytest.raises(ValueError, match="Source 'nonexistent' not found"):
            await scraper.scrape("nonexistent", "test topic")

    @pytest.mark.asyncio
    async def test_scrape_calls_source_extract(self):
        """Test scrape() calls source.extract() with correct parameters."""
        scraper = WebScraper()

        # Mock source
        mock_source = MagicMock()
        mock_content = ScrapedContent(
            source_url="https://example.com",
            title="Test Article",
            raw_text="Test content",
            images=[],
            metadata={'source': 'test'},
            scraped_at=datetime.now(timezone.utc)
        )
        mock_source.extract = AsyncMock(return_value=[mock_content])

        # Mock registry
        scraper.registry.get_source = MagicMock(return_value=mock_source)

        # Mock rate limiter
        scraper.rate_limiter.wait = AsyncMock()

        result = await scraper.scrape("test_source", "test topic", max_pages=2)

        # Verify calls
        scraper.registry.get_source.assert_called_once_with("test_source")
        mock_source.extract.assert_called_once_with(
            "test topic", max_pages=2, allowed=scraper.check_robots_txt)
        scraper.rate_limiter.wait.assert_called_once()

        # Verify result
        assert len(result) == 1
        assert result[0] == mock_content

    @pytest.mark.asyncio
    async def test_scrape_can_skip_robots_txt(self):
        scraper = WebScraper()
        mock_source = MagicMock()
        mock_source.extract = AsyncMock(return_value=[])
        scraper.registry.get_source = MagicMock(return_value=mock_source)
        scraper.rate_limiter.wait = AsyncMock()

        await scraper.scrape("test_source", "test topic", respect_robots=False)

        mock_source.extract.assert_called_once_with("test topic", max_pages=1, allowed=None)

    @pytest.mark.asyncio
    async def test_scrape_propagates_source_errors(self):
        """Test scrape() propagates errors from source.extract()."""
        scraper = WebScraper()

        # Mock source that raises error
        mock_source = MagicMock()
        mock_source.extract = AsyncMock(side_effect=Exception("Extraction failed"))

        scraper.registry.get_source = MagicMock(return_value=mock_source)
        scraper.rate_limiter.wait = AsyncMock()

        with pytest.raises(Exception, match="Extraction failed"):
            await scraper.scrape("test_source", "test topic")


class TestWebScraperScrapeAll:
    """Test scrape_all() method."""

    @pytest.mark.asyncio
    async def test_scrape_all_uses_all_sources_by_default(self):
        """Test scrape_all() uses all registered sources by default."""
        scraper = WebScraper()

        # Mock list_sources
        scraper.list_sources = MagicMock(return_value=["source1", "source2"])

        # Mock scrape to return empty list
        scraper.scrape = AsyncMock(return_value=[])

        await scraper.scrape_all("test topic")

        # Should call scrape for each source
        assert scraper.scrape.call_count == 2

    @pytest.mark.asyncio
    async def test_scrape_all_uses_specified_sources(self):
        """Test scrape_all() uses only specified sources."""
        scraper = WebScraper()

        # Mock scrape
        scraper.scrape = AsyncMock(return_value=[])

        await scraper.scrape_all("test topic", sources=["source1"])

        # Should only call scrape once
        assert scraper.scrape.call_count == 1
        scraper.scrape.assert_called_with("source1", "test topic", 1, True)

    @pytest.mark.asyncio
    async def test_scrape_all_continues_on_error_by_default(self):
        """Test scrape_all() continues when a source fails (fail_fast=False)."""
        scraper = WebScraper()

        mock_content = ScrapedContent(
            source_url="https://example.com",
            title="Test",
            raw_text="Content",
            images=[],
            metadata={},
            scraped_at=datetime.now(timezone.utc)
        )

        # Mock scrape: first fails, second succeeds
        scraper.scrape = AsyncMock(side_effect=[
            Exception("Source 1 failed"),
            [mock_content]
        ])

        result = await scraper.scrape_all(
            "test topic",
            sources=["source1", "source2"],
            fail_fast=False
        )

        # Should return content from successful source
        assert len(result) == 1
        assert result[0] == mock_content

    @pytest.mark.asyncio
    async def test_scrape_all_fails_fast_when_enabled(self):
        """Test scrape_all() raises on first error when fail_fast=True."""
        scraper = WebScraper()

        # Mock scrape to fail
        scraper.scrape = AsyncMock(side_effect=Exception("Source failed"))

        with pytest.raises(Exception, match="Source failed"):
            await scraper.scrape_all(
                "test topic",
                sources=["source1"],
                fail_fast=True
            )
