"""Unit tests for SearchService: the ranked-search call it makes, the articles it reassembles, and autocomplete."""

import json
from unittest.mock import patch

import pytest

from backend.services.search_service import SearchService
from backend.tests.wire import article_blob, article_row, reply, rows, use_wire


class TestSearchArticles:
    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_calls_the_ranked_search_function_with_the_query_and_limit(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, rows())

        results = await SearchService().search_articles("Mauryan Empire", limit=7)

        assert results == []
        (request,) = wire.requests
        assert request.method == "POST"
        assert request.url.path == "/rest/v1/rpc/search_articles"
        assert json.loads(request.content) == {"search_query": "Mauryan Empire", "match_limit": 7}

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_default_limit_is_twenty(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, rows())

        await SearchService().search_articles("Ashoka")

        assert json.loads(wire.requests[0].content)["match_limit"] == 20

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_keeps_the_relevance_order_the_database_returns(self, mock_get_supabase):
        use_wire(mock_get_supabase, rows(article_row("art_2", "Best match"), article_row("art_1", "Weaker match")),
                 blob=article_blob())

        results = await SearchService().search_articles("Ashoka")

        assert [a.id for a in results] == ["art_2", "art_1"]
        assert results[0].sections[0].heading == "Origins"

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_returns_empty_list_when_no_matches(self, mock_get_supabase):
        use_wire(mock_get_supabase, rows())

        assert await SearchService().search_articles("no such topic") == []


class TestAutocomplete:
    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_calls_the_suggestion_function_with_the_prefix_and_limit(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, reply(200, [{"term": "Mauryan Empire"}]))

        await SearchService().autocomplete("mau", limit=7)

        (request,) = wire.requests
        assert request.method == "POST"
        assert request.url.path == "/rest/v1/rpc/autocomplete_suggestions"
        assert json.loads(request.content) == {"prefix": "mau", "match_limit": 7}

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_default_limit_is_ten(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, reply(200, []))

        await SearchService().autocomplete("mau")

        assert json.loads(wire.requests[0].content)["match_limit"] == 10

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_returns_the_terms_in_the_order_the_database_ranked_them(self, mock_get_supabase):
        use_wire(mock_get_supabase, reply(200, [{"term": "Mauryan Empire"}, {"term": "Mauryan Art"}]))

        assert await SearchService().autocomplete("maur") == ["Mauryan Empire", "Mauryan Art"]

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_returns_empty_list_when_nothing_starts_with_the_prefix(self, mock_get_supabase):
        use_wire(mock_get_supabase, reply(200, []))

        assert await SearchService().autocomplete("zzz") == []

    @pytest.mark.asyncio
    @pytest.mark.parametrize("prefix", ["", "   ", "\t\n"])
    @patch("backend.services.search_service.get_supabase")
    async def test_a_blank_prefix_asks_nothing(self, mock_get_supabase, prefix):
        wire = use_wire(mock_get_supabase, reply(200, [{"term": "Everything"}]))

        assert await SearchService().autocomplete(prefix) == []
        assert wire.requests == []

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_sends_the_prefix_as_typed_and_leaves_matching_to_the_database(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, reply(200, []))

        await SearchService().autocomplete("  Ashoka's 50%_ ")

        assert json.loads(wire.requests[0].content)["prefix"] == "  Ashoka's 50%_ "
