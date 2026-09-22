"""LikeService tests. RLS is bypassed on this path, so each query's user_id filter is asserted on the wire."""

import json
from functools import partial
from unittest.mock import patch

import pytest
from postgrest.exceptions import APIError

from backend.services.like_service import ArticleNotFoundError, LikeService
from backend.tests.wire import article_blob, article_row, reply, rows, use_wire

use_admin_wire = partial(use_wire, admin=True)


class TestLikeArticle:
    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_upserts_row_with_conflict_target(self, mock_get_supabase):
        wire = use_admin_wire(mock_get_supabase, rows())

        await LikeService().like_article("user-1", "art_1")

        (request,) = wire.requests
        assert request.method == "POST"
        assert request.url.path == "/rest/v1/likes"
        assert request.url.params["on_conflict"] == "user_id,article_id"
        assert "resolution=merge-duplicates" in request.headers["prefer"]
        assert json.loads(request.content) == {"user_id": "user-1", "article_id": "art_1"}

    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_unknown_article_raises_article_not_found(self, mock_get_supabase):
        error = {
            "code": "23503",
            "message": 'insert or update on table "likes" violates foreign key constraint "likes_article_id_fkey"',
            "details": 'Key (article_id)=(art_missing) is not present in table "articles".',
            "hint": None,
        }
        use_admin_wire(mock_get_supabase, reply(409, error))

        with pytest.raises(ArticleNotFoundError):
            await LikeService().like_article("user-1", "art_missing")

    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_foreign_key_violation_on_the_user_is_not_reported_as_missing_article(self, mock_get_supabase):
        error = {
            "code": "23503",
            "message": 'insert or update on table "likes" violates foreign key constraint "likes_user_id_fkey"',
            "details": 'Key (user_id)=(user-x) is not present in table "users".',
            "hint": None,
        }
        use_admin_wire(mock_get_supabase, reply(409, error))

        with pytest.raises(APIError):
            await LikeService().like_article("user-x", "art_1")

    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_other_database_errors_propagate(self, mock_get_supabase):
        error = {"code": "42501", "message": "permission denied", "details": None, "hint": None}
        use_admin_wire(mock_get_supabase, reply(403, error))

        with pytest.raises(APIError):
            await LikeService().like_article("user-1", "art_1")


class TestUnlikeArticle:
    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_deletes_only_this_users_row_for_this_article(self, mock_get_supabase):
        wire = use_admin_wire(mock_get_supabase, reply(204))

        await LikeService().unlike_article("user-1", "art_1")

        (request,) = wire.requests
        assert request.method == "DELETE"
        assert request.url.path == "/rest/v1/likes"
        assert request.url.params["user_id"] == "eq.user-1"
        assert request.url.params["article_id"] == "eq.art_1"


class TestIsLiked:
    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_true_when_row_present_and_query_is_scoped_to_the_user(self, mock_get_supabase):
        wire = use_admin_wire(mock_get_supabase, rows({"article_id": "art_1"}))

        assert await LikeService().is_liked("user-1", "art_1") is True

        (request,) = wire.requests
        assert request.method == "GET"
        assert request.url.params["select"] == "article_id"
        assert request.url.params["user_id"] == "eq.user-1"
        assert request.url.params["article_id"] == "eq.art_1"
        assert request.url.params["limit"] == "1"

    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_false_when_no_row(self, mock_get_supabase):
        use_admin_wire(mock_get_supabase, rows())

        assert await LikeService().is_liked("user-1", "art_1") is False


class TestGetUserLikes:
    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_returns_full_articles_most_recent_first_scoped_to_the_user(self, mock_get_supabase):
        liked = [
            {"created_at": "2026-07-05T00:00:00Z", "articles": article_row("art_2", "Second")},
            {"created_at": "2026-07-04T00:00:00Z", "articles": article_row("art_1", "First")},
        ]
        wire = use_admin_wire(mock_get_supabase, rows(*liked), blob=article_blob())

        articles = await LikeService().get_user_likes("user-1")

        assert [a.id for a in articles] == ["art_2", "art_1"]
        assert articles[0].sections[0].heading == "Origins"
        (request,) = wire.requests
        assert request.method == "GET"
        assert request.url.path == "/rest/v1/likes"
        assert request.url.params["select"] == "created_at,articles(*)"
        assert request.url.params["user_id"] == "eq.user-1"
        assert request.url.params["order"] == "created_at.desc"
        assert request.url.params["limit"] == "20"

    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_passes_custom_limit(self, mock_get_supabase):
        wire = use_admin_wire(mock_get_supabase, rows())

        await LikeService().get_user_likes("user-1", limit=5)

        assert wire.requests[0].url.params["limit"] == "5"

    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_empty_when_no_likes(self, mock_get_supabase):
        use_admin_wire(mock_get_supabase, rows())

        assert await LikeService().get_user_likes("user-1") == []


class TestGetArticleLikeCount:
    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_reads_the_total_from_a_count_only_request(self, mock_get_supabase):
        # With limit(0) PostgREST returns an empty list and the total in Content-Range.
        wire = use_admin_wire(mock_get_supabase, reply(200, [], {"content-range": "*/7"}))

        assert await LikeService().get_article_like_count("art_1") == 7

        (request,) = wire.requests
        assert request.method == "GET"
        assert request.url.path == "/rest/v1/likes"
        assert request.url.params["select"] == "id"
        assert request.url.params["article_id"] == "eq.art_1"
        assert request.url.params["limit"] == "0"
        assert request.headers["prefer"] == "count=exact"

    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_zero_when_no_count_is_returned(self, mock_get_supabase):
        use_admin_wire(mock_get_supabase, rows())

        assert await LikeService().get_article_like_count("art_1") == 0
