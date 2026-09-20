"""Unit tests for ArticleService.list_recent_articles: the paging query it sends and the articles it returns."""

from unittest.mock import patch

import httpx
import pytest

from backend.services.article_service import ArticleService
from backend.tests.wire import article_blob, article_row, rows, use_wire


class TestListRecentArticles:
    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_sends_a_total_newest_first_order_with_offset_and_limit(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, rows())

        await ArticleService().list_recent_articles(limit=20, offset=40)

        (request,) = wire.requests
        assert request.url.path == "/rest/v1/articles"
        # created_at and id break ties, so the order is total and pages cannot overlap.
        assert request.url.params["order"] == "date.desc,created_at.desc,id.desc"
        assert request.url.params["offset"] == "40"
        assert request.url.params["limit"] == "20"

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_defaults_to_the_first_five(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, rows())

        await ArticleService().list_recent_articles()

        assert wire.requests[0].url.params["offset"] == "0"
        assert wire.requests[0].url.params["limit"] == "5"

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_returns_full_articles_in_response_order(self, mock_get_supabase):
        use_wire(mock_get_supabase, rows(article_row("art_2", "Second"), article_row("art_1", "First")),
                 blob=article_blob())

        articles = await ArticleService().list_recent_articles()

        assert [a.id for a in articles] == ["art_2", "art_1"]
        assert articles[0].sections[0].heading == "Origins"

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_returns_an_empty_list_when_there_are_no_articles(self, mock_get_supabase):
        use_wire(mock_get_supabase, rows())

        assert await ArticleService().list_recent_articles() == []

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_pages_together_cover_every_article_exactly_once(self, mock_get_supabase):
        every = [article_row(f"art_{n:02d}") for n in range(7, 0, -1)]  # newest first: art_07 ... art_01

        def serve(request):  # stands in for PostgREST honouring offset and limit
            offset, limit = int(request.url.params["offset"]), int(request.url.params["limit"])
            return httpx.Response(200, json=every[offset:offset + limit])

        use_wire(mock_get_supabase, serve, blob=article_blob())
        service = ArticleService()

        pages = [await service.list_recent_articles(limit=3, offset=offset) for offset in (0, 3, 6)]

        assert [a.id for page in pages for a in page] == [row["id"] for row in every]
