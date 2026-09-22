"""Unit tests for ArticleService.get_daily_article: the ordering it sends and the article it returns."""

from unittest.mock import patch

import pytest

from backend.services.article_service import ArticleService
from backend.tests.wire import article_blob, article_row, rows, use_wire


class TestGetDailyArticle:
    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_returns_none_when_no_articles(self, mock_get_supabase):
        use_wire(mock_get_supabase, rows())

        assert await ArticleService().get_daily_article() is None

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_sorts_newest_date_first_then_newest_created_first(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, rows())

        await ArticleService().get_daily_article()

        (request,) = wire.requests
        assert request.url.path == "/rest/v1/articles"
        # created_at breaks the tie when two articles share a date.
        assert request.url.params["order"] == "date.desc,created_at.desc"
        assert request.url.params["limit"] == "1"

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_returns_the_first_row_as_a_full_article(self, mock_get_supabase):
        use_wire(mock_get_supabase, rows(article_row()), blob=article_blob())

        article = await ArticleService().get_daily_article()

        assert article.id == "art_20260703_001"
        assert article.sections[0].heading == "Origins"
