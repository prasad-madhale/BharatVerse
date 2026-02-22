"""
Integration tests for the web scraper.

These tests make real API calls and scrape real content.
Run with: pytest tests/scrapper/test_integration.py -v
"""

import pytest
from scrapper import WebScraper
from scrapper.sources import registry


@pytest.mark.asyncio
@pytest.mark.integration
class TestScraperIntegration:
    """Integration tests for the complete scraping pipeline."""

    async def test_search_and_scrape_wikipedia(self):
        """Test scraping from Wikipedia."""
        scraper = WebScraper()

        contents = await scraper.search_and_scrape(
            "Python programming language",
            max_pages_per_source=1,
            sources=["wikipedia"]
        )

        assert len(contents) > 0
        content = contents[0]

        # Verify content structure
        assert content.title is not None
        assert len(content.raw_text) > 0
        assert content.source_url.startswith("https://")
        assert content.metadata['source'] == 'wikipedia'
        assert 'word_count' in content.metadata
        assert content.metadata['word_count'] > 0

    async def test_search_and_scrape_multiple_pages(self):
        """Test scraping multiple pages from Wikipedia."""
        scraper = WebScraper()

        contents = await scraper.search_and_scrape(
            "Shivaji Maharaj",
            max_pages_per_source=5,
            sources=["wikipedia"]
        )

        assert len(contents) > 0
        assert len(contents) <= 3

        # Verify all contents are valid
        for content in contents:
            assert content.title is not None
            assert len(content.raw_text) > 0
            assert content.metadata['source'] == 'wikipedia'

    async def test_search_and_scrape_all_sources(self):
        """Test scraping from all sources."""
        scraper = WebScraper()

        contents = await scraper.search_and_scrape(
            "Mauryan Empire",
            max_pages_per_source=5
        )

        # Should get results from at least one source
        assert len(contents) > 0

        # Check that we have content from different sources
        sources = set(c.metadata['source'] for c in contents)
        assert len(sources) > 0

    async def test_direct_source_search(self):
        """Test direct source access for search."""
        wiki = registry.get_source('wikipedia')
        results = wiki.search_topic("India", max_results=5)

        assert len(results) > 0
        assert len(results) <= 5

        # Verify result structure
        for result in results:
            assert 'title' in result
            assert 'url' in result
            assert 'summary' in result
            assert len(result['summary']) > 0

    async def test_archive_org_search(self):
        """Test Archive.org search."""
        archive = registry.get_source('archive_org')
        results = archive.search_topic("ancient history", max_results=3)

        assert isinstance(results, list)
        assert len(results) > 0

        for result in results:
            assert 'title' in result
            assert 'url' in result
            assert 'identifier' in result
