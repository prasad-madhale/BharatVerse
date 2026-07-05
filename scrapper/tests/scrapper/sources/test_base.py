"""
Unit tests for ContentSource's default extract()/_scrape_url() implementation.

Uses a minimal concrete subclass since ContentSource is abstract, and mocks
AsyncWebCrawler so no real browser/network activity happens.
"""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from scrapper.models.article import ScrapedContent
from scrapper.sources.base import ContentSource


class _StubSource(ContentSource):
    """Minimal concrete ContentSource for exercising the base class's defaults."""

    name = "stub"

    def search_topic(self, topic, max_results=5):
        return [{"title": "Stub Title", "url": "https://example.com/stub", "summary": "Stub summary"}]


def _make_crawler_class(crawl_result):
    """Build a mock AsyncWebCrawler class whose instances act as an async context manager."""
    crawler_instance = MagicMock()
    crawler_instance.arun = AsyncMock(return_value=crawl_result)
    crawler_instance.__aenter__ = AsyncMock(return_value=crawler_instance)
    crawler_instance.__aexit__ = AsyncMock(return_value=False)
    return MagicMock(return_value=crawler_instance)


class TestScrapeUrl:
    async def test_scrape_url_with_markdown_generation_result(self):
        crawl_result = MagicMock()
        crawl_result.success = True
        crawl_result.markdown = MagicMock(raw_markdown="# Heading\n\nSome content.")
        crawl_result.media = {}
        crawl_result.metadata = {}

        with patch('scrapper.sources.base.AsyncWebCrawler', _make_crawler_class(crawl_result)):
            source = _StubSource()
            content = await source._scrape_url(
                {"title": "Stub Title", "url": "https://example.com/stub", "summary": "..."}
            )

        assert isinstance(content, ScrapedContent)
        assert content.raw_text == "# Heading\n\nSome content."
        assert content.title == "Stub Title"
        assert content.metadata['source'] == "stub"
        assert content.images == []

    async def test_scrape_url_with_plain_string_markdown(self):
        crawl_result = MagicMock()
        crawl_result.success = True
        crawl_result.markdown = "Plain markdown string"
        crawl_result.media = {}
        crawl_result.metadata = {}

        with patch('scrapper.sources.base.AsyncWebCrawler', _make_crawler_class(crawl_result)):
            source = _StubSource()
            content = await source._scrape_url({"title": "Stub Title", "url": "https://example.com/stub"})

        assert content.raw_text == "Plain markdown string"

    async def test_scrape_url_unexpected_markdown_type_raises(self):
        crawl_result = MagicMock()
        crawl_result.success = True
        crawl_result.markdown = 12345  # neither an object with raw_markdown nor a str
        crawl_result.media = {}
        crawl_result.metadata = {}

        with patch('scrapper.sources.base.AsyncWebCrawler', _make_crawler_class(crawl_result)):
            source = _StubSource()
            with pytest.raises(Exception, match="Unexpected markdown format"):
                await source._scrape_url({"title": "Stub Title", "url": "https://example.com/stub"})

    async def test_scrape_url_extracts_images(self):
        crawl_result = MagicMock()
        crawl_result.success = True
        crawl_result.markdown = "content"
        crawl_result.media = {
            'images': [{'src': 'https://example.com/1.jpg', 'alt': 'Alt text', 'title': 'Caption'}],
        }
        crawl_result.metadata = {}

        with patch('scrapper.sources.base.AsyncWebCrawler', _make_crawler_class(crawl_result)):
            source = _StubSource()
            content = await source._scrape_url({"title": "Stub Title", "url": "https://example.com/stub"})

        assert content.images == [{'url': 'https://example.com/1.jpg', 'alt_text': 'Alt text', 'caption': 'Caption'}]

    async def test_scrape_url_failure_raises(self):
        crawl_result = MagicMock()
        crawl_result.success = False
        crawl_result.error_message = "boom"

        with patch('scrapper.sources.base.AsyncWebCrawler', _make_crawler_class(crawl_result)):
            source = _StubSource()
            with pytest.raises(Exception, match="Failed to scrape"):
                await source._scrape_url({"title": "Stub Title", "url": "https://example.com/stub"})

    async def test_scrape_url_falls_back_to_crawl_result_title(self):
        crawl_result = MagicMock()
        crawl_result.success = True
        crawl_result.markdown = "content"
        crawl_result.media = {}
        crawl_result.metadata = {"title": "Fallback Title"}

        with patch('scrapper.sources.base.AsyncWebCrawler', _make_crawler_class(crawl_result)):
            source = _StubSource()
            content = await source._scrape_url({"url": "https://example.com/stub"})  # no 'title' key

        assert content.title == "Fallback Title"


class TestExtract:
    async def test_extract_raises_when_no_results(self):
        source = _StubSource()
        source.search_topic = lambda topic, max_results=5: []

        with pytest.raises(ValueError, match="No results found"):
            await source.extract("Some Topic")

    async def test_extract_returns_scraped_content_for_each_result(self):
        crawl_result = MagicMock()
        crawl_result.success = True
        crawl_result.markdown = "content"
        crawl_result.media = {}
        crawl_result.metadata = {}

        with patch('scrapper.sources.base.AsyncWebCrawler', _make_crawler_class(crawl_result)):
            source = _StubSource()
            contents = await source.extract("Some Topic", max_pages=1)

        assert len(contents) == 1
        assert contents[0].title == "Stub Title"

    async def test_extract_filters_out_failed_pages(self):
        source = _StubSource()
        source.search_topic = lambda topic, max_results=5: [
            {"title": "Good", "url": "https://example.com/good"},
            {"title": "Bad", "url": "https://example.com/bad"},
        ]

        async def fake_scrape_url(result):
            if result["title"] == "Bad":
                raise Exception("scrape failed")
            return ScrapedContent(source_url=result["url"], title=result["title"], raw_text="text")

        with patch.object(source, '_scrape_url', side_effect=fake_scrape_url):
            contents = await source.extract("Some Topic", max_pages=2)

        assert len(contents) == 1
        assert contents[0].title == "Good"
