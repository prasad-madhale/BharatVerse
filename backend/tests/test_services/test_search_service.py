"""Unit tests for SearchService: the query it sends and the articles it reassembles."""

from unittest.mock import patch

import pytest

from backend.services.search_service import SearchService
from backend.tests.wire import article_blob, article_row, rows, use_wire


class TestSearchArticles:
    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_sends_websearch_query_ordered_by_date_with_limit(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, rows())

        results = await SearchService().search_articles("Mauryan Empire", limit=7)

        assert results == []
        (request,) = wire.requests
        assert request.url.path == "/rest/v1/articles"
        assert request.url.params["select"] == "*"
        # wfts is PostgREST's websearch_to_tsquery operator; the strict fts operator rejects a two-word query.
        assert request.url.params["search_vector"] == "wfts(english).Mauryan Empire"
        assert request.url.params["order"] == "date.desc"
        assert request.url.params["limit"] == "7"

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_default_limit_is_twenty(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, rows())

        await SearchService().search_articles("Ashoka")

        assert wire.requests[0].url.params["limit"] == "20"

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_reassembles_full_articles_from_matched_rows(self, mock_get_supabase):
        use_wire(mock_get_supabase, rows(article_row()), blob=article_blob())

        results = await SearchService().search_articles("Ashoka")

        assert len(results) == 1
        assert results[0].id == "art_20260703_001"
        assert results[0].title == "The Mauryan Empire"
        assert results[0].sections[0].heading == "Origins"

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_returns_empty_list_when_no_matches(self, mock_get_supabase):
        use_wire(mock_get_supabase, rows())

        assert await SearchService().search_articles("no such topic") == []
