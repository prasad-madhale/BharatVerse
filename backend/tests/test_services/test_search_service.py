"""
Unit tests for SearchService.

The query-shape tests drive the real service through a real postgrest query
builder (see backend/tests/wire.py) and assert on the HTTP request that would
be sent to Supabase. A mock-based test cannot catch a wrong operator name or
a wrong builder-call order, and both went unnoticed once already.
"""

import json
from unittest.mock import MagicMock, patch

import httpx
import pytest

from backend.services.search_service import SearchService
from backend.tests.wire import WireClient


def make_row(article_id="art_20260703_001", title="The Mauryan Empire"):
    return {
        "id": article_id,
        "title": title,
        "summary": "A summary.",
        "date": "2026-07-03",
        "reading_time_minutes": 13,
        "author": "BharatVerse AI",
        "tags": ["mauryan-empire"],
        "image_url": None,
        "content_file_path": f"articles/2026-07-03/{article_id}.json",
        "created_at": "2026-07-03T00:00:00Z",
        "updated_at": "2026-07-03T00:00:00Z",
    }


def make_blob():
    return json.dumps({
        "content": "## Origins\n\nSome content.",
        "sections": [{"heading": "Origins", "content": "Some content.", "order": 1}],
        "citations": [],
    }).encode("utf-8")


class TestSearchArticles:
    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_sends_websearch_query_ordered_by_date_with_limit(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[]))
        mock_get_supabase.return_value.get_client.return_value = wire

        results = await SearchService().search_articles("Mauryan Empire", limit=7)

        assert results == []
        (request,) = wire.requests
        assert request.url.path == "/rest/v1/articles"
        assert request.url.params["select"] == "*"
        # wfts is PostgREST's websearch_to_tsquery operator. The strict fts
        # operator would reject a two-word query like this one.
        assert request.url.params["search_vector"] == "wfts(english).Mauryan Empire"
        assert request.url.params["order"] == "date.desc"
        assert request.url.params["limit"] == "7"

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_default_limit_is_twenty(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[]))
        mock_get_supabase.return_value.get_client.return_value = wire

        await SearchService().search_articles("Ashoka")

        assert wire.requests[0].url.params["limit"] == "20"

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_reassembles_full_articles_from_matched_rows(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[make_row()]))
        wire.storage = MagicMock()
        wire.storage.from_.return_value.download.return_value = make_blob()
        mock_get_supabase.return_value.get_client.return_value = wire

        results = await SearchService().search_articles("Ashoka")

        assert len(results) == 1
        assert results[0].id == "art_20260703_001"
        assert results[0].title == "The Mauryan Empire"
        assert results[0].sections[0].heading == "Origins"

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_returns_empty_list_when_no_matches(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[]))
        mock_get_supabase.return_value.get_client.return_value = wire

        assert await SearchService().search_articles("no such topic") == []
