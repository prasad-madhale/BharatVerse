"""
Unit tests for ArticleService.get_daily_article.

The ordering test drives the real service through a real postgrest query
builder (see backend/tests/wire.py) and asserts on the HTTP request that
would be sent, so a wrong sort key or a wrong call order cannot pass unseen.
"""

import json
from unittest.mock import MagicMock, patch

import httpx
import pytest

from backend.services.article_service import ArticleService
from backend.tests.wire import WireClient


def make_row(article_id="art_20260703_001"):
    return {
        "id": article_id,
        "title": "The Mauryan Empire",
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


class TestGetDailyArticle:
    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_returns_none_when_no_articles(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[]))
        mock_get_supabase.return_value.get_client.return_value = wire

        assert await ArticleService().get_daily_article() is None

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_sorts_newest_date_first_then_newest_created_first(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[]))
        mock_get_supabase.return_value.get_client.return_value = wire

        await ArticleService().get_daily_article()

        (request,) = wire.requests
        assert request.url.path == "/rest/v1/articles"
        # Two sort keys reach PostgREST as one comma-joined order parameter.
        # created_at is the tie-break when two articles share a date.
        assert request.url.params["order"] == "date.desc,created_at.desc"
        assert request.url.params["limit"] == "1"

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_returns_the_first_row_as_a_full_article(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[make_row()]))
        wire.storage = MagicMock()
        wire.storage.from_.return_value.download.return_value = make_blob()
        mock_get_supabase.return_value.get_client.return_value = wire

        article = await ArticleService().get_daily_article()

        assert article.id == "art_20260703_001"
        assert article.sections[0].heading == "Origins"
