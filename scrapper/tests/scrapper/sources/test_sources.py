"""
Unit tests for content sources.
"""

from scrapper.sources.wikipedia import WikipediaSource
from scrapper.sources.archive_org import ArchiveOrgSource
from scrapper.sources.new_world_encyclopedia import NewWorldEncyclopediaSource


class TestWikipediaSource:
    """Tests for WikipediaSource."""

    def test_init(self):
        """Test Wikipedia source initialization."""
        source = WikipediaSource()
        assert source.name == "wikipedia"
        assert source.browser_config is not None
        assert source.crawler_config is not None

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
