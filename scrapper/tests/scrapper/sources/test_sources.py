"""
Unit tests for content sources.
"""

import pytest

from scrapper.sources.wikipedia import WikipediaSource
from scrapper.sources.archive_org import ArchiveOrgSource
from scrapper.sources.new_world_encyclopedia import NewWorldEncyclopediaSource
from scrapper.sources.indian_culture import IndianCultureSource, SEARCH_ATTEMPTS


class TestWikipediaSource:
    """Tests for WikipediaSource."""

    def test_init(self):
        """Test Wikipedia source initialization."""
        source = WikipediaSource()
        assert source.name == "wikipedia"
        assert source.browser_config is not None
        assert source.crawler_config is not None

    def test_crawler_config_scopes_to_main_content_area(self):
        """Regression test: extraction must be scoped to #mw-content-text, not the
        full page -- otherwise navigation chrome dominates the first several
        thousand characters of extracted markdown, crowding out real article text."""
        source = WikipediaSource()
        assert source.crawler_config.css_selector == "#mw-content-text"

    def test_search_topic_returns_results(self):
        """Test that search_topic returns results for valid topic."""
        source = WikipediaSource()
        results = source.search_topic("Python programming", max_results=3)

        assert isinstance(results, list)
        assert len(results) > 0
        assert len(results) <= 3

        # Check result structure
        for result in results:
            assert 'title' in result
            assert 'url' in result
            assert 'summary' in result
            assert 'page_id' in result
            assert isinstance(result['title'], str)
            assert result['url'].startswith('https://')

    def test_search_topic_empty_for_invalid(self):
        """Test that search_topic returns empty list for invalid topic."""
        source = WikipediaSource()
        results = source.search_topic("xyzabc123nonexistent", max_results=3)

        assert isinstance(results, list)
        assert len(results) == 0

    def test_search_topic_respects_max_results(self):
        """Test that search_topic respects max_results parameter."""
        source = WikipediaSource()
        results = source.search_topic("India", max_results=2)

        assert len(results) <= 2

    def test_get_page_info_valid_title(self):
        """Test _get_page_info with valid title."""
        source = WikipediaSource()
        result = source._get_page_info("Python (programming language)")

        assert result is not None
        assert 'title' in result
        assert 'url' in result
        assert 'summary' in result
        assert 'page_id' in result

    def test_get_page_info_invalid_title(self):
        """Test _get_page_info with invalid title."""
        source = WikipediaSource()
        result = source._get_page_info("NonexistentPage123XYZ")

        assert result is None


class TestArchiveOrgSource:
    """Tests for ArchiveOrgSource."""

    def test_init(self):
        """Test Archive.org source initialization."""
        source = ArchiveOrgSource()
        assert source.name == "archive_org"
        assert source.browser_config is not None
        assert source.crawler_config is not None

    def test_search_topic_returns_results(self):
        """Test that search_topic returns results."""
        source = ArchiveOrgSource()
        results = source.search_topic("ancient india", max_results=3)

        assert isinstance(results, list)
        # Archive.org might return 0 results for some queries
        if len(results) > 0:
            assert len(results) <= 3

            # Check result structure
            for result in results:
                assert 'title' in result
                assert 'url' in result
                assert 'summary' in result
                assert 'identifier' in result
                assert result['url'].startswith('https://archive.org/')

    def test_search_topic_respects_max_results(self):
        """Test that search_topic respects max_results parameter."""
        source = ArchiveOrgSource()
        results = source.search_topic("history", max_results=2)

        assert len(results) <= 2

    def test_search_topic_restricts_to_texts(self):
        """Regression test: an unrestricted search over Archive.org's whole catalog can surface a
        video, an image or another item with no useful text to scrape (found for "Rani ki Vav":
        a YouTube video and an unrelated art collection outranked the real reference texts)."""
        source = ArchiveOrgSource()
        results = source.search_topic("Rani ki Vav", max_results=5)

        assert results
        assert all(r["mediatype"] == "texts" for r in results)


class TestNewWorldEncyclopediaSource:
    """Tests for NewWorldEncyclopediaSource."""

    def test_init(self):
        """Test New World Encyclopedia source initialization."""
        source = NewWorldEncyclopediaSource()
        assert source.name == "new_world_encyclopedia"
        assert source.browser_config is not None
        assert source.crawler_config is not None

    def test_search_topic_guesses_entry_url(self):
        """Test that search_topic builds the direct /entry/{Topic} URL guess."""
        source = NewWorldEncyclopediaSource()
        results = source.search_topic("Chandragupta Maurya")

        assert results == [{
            "title": "Chandragupta Maurya",
            "url": "https://www.newworldencyclopedia.org/entry/Chandragupta_Maurya",
            "summary": "Chandragupta Maurya",
        }]

    def test_search_topic_strips_surrounding_whitespace(self):
        """Test that search_topic normalizes surrounding whitespace before building the URL."""
        source = NewWorldEncyclopediaSource()
        results = source.search_topic("  Kalinga War  ")

        assert results[0]["url"] == "https://www.newworldencyclopedia.org/entry/Kalinga_War"

    def test_search_topic_ignores_max_results(self):
        """Test that search_topic always returns exactly one candidate regardless of max_results."""
        source = NewWorldEncyclopediaSource()
        results = source.search_topic("Ashoka", max_results=5)

        assert len(results) == 1


class _FailingAsyncBrowser:
    """A fake browser whose new_page() always raises, to test the async retry loop deterministically
    (the live site's flakiness confirmed a real failure mode, but isn't reliable enough to test against)."""

    def __init__(self):
        self.new_page_calls = 0

    async def new_page(self):
        self.new_page_calls += 1
        raise RuntimeError("boom")


class _FailingSyncBrowser:
    """Sync counterpart of _FailingAsyncBrowser, for search_topic's retry loop."""

    def __init__(self):
        self.new_page_calls = 0

    def new_page(self):
        self.new_page_calls += 1
        raise RuntimeError("boom")


async def _no_sleep_async(seconds):
    pass


class TestIndianCultureSource:
    """Tests for IndianCultureSource."""

    def test_init(self):
        source = IndianCultureSource()
        assert source.name == "indian_culture"

    def test_search_topic_returns_results(self):
        """A topic with real coverage (see the source's docstring) returns real results."""
        source = IndianCultureSource()
        results = source.search_topic("Ashoka", max_results=3)

        assert isinstance(results, list)
        assert len(results) > 0
        for result in results:
            assert "title" in result
            assert "url" in result
            assert "summary" in result
            assert result["url"].startswith("https://www.indianculture.gov.in/")

    def test_search_topic_empty_for_nonsense_query(self):
        source = IndianCultureSource()
        results = source.search_topic("xyzabc123nonexistentquery", max_results=3)

        assert results == []

    async def test_extract_returns_real_content(self):
        source = IndianCultureSource()
        contents = await source.extract("Ashoka", max_pages=2)

        assert len(contents) > 0
        for content in contents:
            assert content.source_url.startswith("https://www.indianculture.gov.in/")
            assert len(content.raw_text) > 500
            assert content.metadata["source"] == "indian_culture"

    async def test_extract_raises_when_nothing_has_real_content(self):
        """Regression test: most catalog items are archival-record metadata with no body text
        (see the source's docstring) -- a topic that only matches those must not be treated as a
        successful, empty extraction, since a raised exception is what lets web_scraper.py's
        scrape_all() log it and continue with the other sources rather than silently publishing
        nothing from this source."""
        source = IndianCultureSource()

        with pytest.raises(ValueError, match="No Indian Culture Portal results"):
            await source.extract("xyzabc123nonexistentquery", max_pages=2)

    async def test_search_async_retries_then_raises_the_last_error(self, monkeypatch):
        # Regression test: new_page() used to be called outside the try block, so a failure there
        # skipped the retry loop entirely instead of being retried like any other failure.
        monkeypatch.setattr("scrapper.sources.indian_culture.asyncio.sleep", _no_sleep_async)
        source = IndianCultureSource()
        browser = _FailingAsyncBrowser()

        with pytest.raises(RuntimeError, match="boom"):
            await source._search_async(browser, "Ashoka")

        assert browser.new_page_calls == SEARCH_ATTEMPTS

    def test_search_sync_retries_then_raises_the_last_error(self, monkeypatch):
        monkeypatch.setattr("scrapper.sources.indian_culture.time.sleep", lambda seconds: None)
        source = IndianCultureSource()
        browser = _FailingSyncBrowser()

        with pytest.raises(RuntimeError, match="boom"):
            source._search_sync(browser, "Ashoka")

        assert browser.new_page_calls == SEARCH_ATTEMPTS


class TestSourceRegistry:
    """Tests for SourceRegistry."""

    def test_register_and_get_source(self):
        """Test registering and retrieving sources."""
        from scrapper.sources.base import SourceRegistry

        registry = SourceRegistry()
        wiki = WikipediaSource()

        registry.register(wiki)

        assert "wikipedia" in registry.list_sources()
        assert registry.get_source("wikipedia") == wiki

    def test_get_nonexistent_source(self):
        """Test getting a source that doesn't exist."""
        from scrapper.sources.base import SourceRegistry

        registry = SourceRegistry()

        assert registry.get_source("nonexistent") is None

    def test_list_sources(self):
        """Test listing all registered sources."""
        from scrapper.sources.base import SourceRegistry

        registry = SourceRegistry()
        wiki = WikipediaSource()
        archive = ArchiveOrgSource()
        nwe = NewWorldEncyclopediaSource()

        registry.register(wiki)
        registry.register(archive)
        registry.register(nwe)

        sources = registry.list_sources()
        assert "wikipedia" in sources
        assert "archive_org" in sources
        assert "new_world_encyclopedia" in sources
        assert len(sources) == 3
