"""
Unit tests for SearchService.

Tests the text_search query shape and row assembly with a mocked Supabase
client (no live network calls) -- same convention as
test_article_service.py.
"""

import json

import pytest
from unittest.mock import MagicMock, patch

from backend.services.search_service import SearchService


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


@pytest.fixture
def mock_settings():
    settings = MagicMock()
    settings.articles_storage_bucket = "articles"
    return settings


@pytest.fixture
def mock_supabase_client():
    return MagicMock()


class TestSearchArticles:
    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_queries_search_vector_with_websearch_semantics(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        query = mock_supabase_client.table.return_value.select.return_value.text_search.return_value
        query.order.return_value.limit.return_value.execute.return_value.data = []

        service = SearchService()
        await service.search_articles("Ashoka")

        mock_supabase_client.table.assert_called_with("articles")
        mock_supabase_client.table.return_value.select.return_value.text_search.assert_called_once_with(
            "search_vector", "Ashoka", options={"type": "websearch", "config": "english"}
        )

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_passes_limit_and_orders_by_date_descending(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        query = mock_supabase_client.table.return_value.select.return_value.text_search.return_value
        query.order.return_value.limit.return_value.execute.return_value.data = []

        service = SearchService()
        await service.search_articles("Ashoka", limit=5)

        query.order.assert_called_once_with("date", desc=True)
        query.order.return_value.limit.assert_called_once_with(5)

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_reassembles_full_articles_from_matched_rows(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        query = mock_supabase_client.table.return_value.select.return_value.text_search.return_value
        query.order.return_value.limit.return_value.execute.return_value.data = [make_row()]
        mock_supabase_client.storage.from_.return_value.download.return_value = make_blob()

        service = SearchService()
        results = await service.search_articles("Ashoka")

        assert len(results) == 1
        assert results[0].id == "art_20260703_001"
        assert results[0].title == "The Mauryan Empire"
        assert results[0].sections[0].heading == "Origins"

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_returns_empty_list_when_no_matches(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        query = mock_supabase_client.table.return_value.select.return_value.text_search.return_value
        query.order.return_value.limit.return_value.execute.return_value.data = []

        service = SearchService()
        results = await service.search_articles("no such topic")

        assert results == []
