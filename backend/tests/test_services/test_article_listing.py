"""Unit tests for ArticleService.list_recent_articles: the paging query it sends and the articles it returns."""

import asyncio
from unittest.mock import patch

import httpx
import pytest
from hypothesis import given, settings, strategies as st

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

    @settings(max_examples=60, deadline=None)
    @given(total=st.integers(min_value=0, max_value=60), limit=st.integers(min_value=1, max_value=20))
    def test_pages_together_cover_every_article_exactly_once(self, total, limit):
        """Property 20: for any table size and page size, the union of the pages is the whole set, in order."""
        every = [article_row(f"art_{n:03d}") for n in range(total, 0, -1)]  # newest first

        def serve(request):  # stands in for PostgREST honouring offset and limit
            offset, size = int(request.url.params["offset"]), int(request.url.params["limit"])
            return httpx.Response(200, json=every[offset:offset + size])

        async def read_every_page():
            service, seen, offset = ArticleService(), [], 0
            while True:  # stop on a short page, as the app does
                page = await service.list_recent_articles(limit=limit, offset=offset)
                seen += [a.id for a in page]
                if len(page) < limit:
                    return seen
                offset += limit

        with patch("backend.services.article_service.get_supabase") as mock_get_supabase:
            use_wire(mock_get_supabase, serve, blob=article_blob())
            assert asyncio.run(read_every_page()) == [row["id"] for row in every]
