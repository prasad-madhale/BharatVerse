"""
Unit tests for WebScraper.

Tests scraper logic with mocked sources and rate limiter.
"""

import pytest
from unittest.mock import MagicMock, AsyncMock, patch
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


class TestWebScraperRobotsTxt:
    """Test robots.txt checking."""

    @pytest.mark.asyncio
    async def test_check_robots_txt_allowed(self):
        """Test check_robots_txt() returns True when allowed."""
        scraper = WebScraper()

        with patch('scrapper.web_scraper.RobotFileParser') as mock_parser_class:
            mock_parser = MagicMock()
            mock_parser.can_fetch.return_value = True
            mock_parser_class.return_value = mock_parser

            result = await scraper.check_robots_txt("https://example.com/page")

            assert result is True
            mock_parser.can_fetch.assert_called_once()

    @pytest.mark.asyncio
    async def test_check_robots_txt_disallowed(self):
        """Test check_robots_txt() returns False when disallowed."""
        scraper = WebScraper()

        with patch('scrapper.web_scraper.RobotFileParser') as mock_parser_class:
            mock_parser = MagicMock()
            mock_parser.can_fetch.return_value = False
            mock_parser_class.return_value = mock_parser

            result = await scraper.check_robots_txt("https://example.com/admin")

            assert result is False

    @pytest.mark.asyncio
    async def test_check_robots_txt_caches_result(self):
        """Test robots.txt results are cached."""
        scraper = WebScraper()

        with patch('scrapper.web_scraper.RobotFileParser') as mock_parser_class:
            mock_parser = MagicMock()
            mock_parser.can_fetch.return_value = True
            mock_parser_class.return_value = mock_parser

            # First call
            await scraper.check_robots_txt("https://example.com/page1")

            # Second call to same domain
            await scraper.check_robots_txt("https://example.com/page2")

            # Should only create parser once (cached)
            assert mock_parser_class.call_count == 1

    @pytest.mark.asyncio
    async def test_check_robots_txt_fetch_failure_allows(self):
        """Test robots.txt fetch failure defaults to allowing."""
        scraper = WebScraper()

        with patch('scrapper.web_scraper.RobotFileParser') as mock_parser_class:
            mock_parser = MagicMock()
            mock_parser.read.side_effect = Exception("Network error")
            mock_parser_class.return_value = mock_parser

            result = await scraper.check_robots_txt("https://example.com/page")

            # Should default to True when robots.txt can't be fetched
            assert result is True


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
        mock_source.extract.assert_called_once_with("test topic", max_pages=2)
        scraper.rate_limiter.wait.assert_called_once()

        # Verify result
        assert len(result) == 1
        assert result[0] == mock_content

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
        scraper.scrape.assert_called_with("source1", "test topic", 1, False)

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
