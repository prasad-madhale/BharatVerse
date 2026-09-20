---
id: TASK-004
title: Add LikeService, the data layer for article likes
depends_on: TASK-001
requires: py:postgrest, py:httpx
allowed: backend/services/like_service.py, backend/tests/test_services/test_like_service.py
verify: cd "$BV_ROOT/backend" && python -m pytest tests/test_services/test_like_service.py -q --no-cov -p no:cacheprovider
verify: cd "$BV_ROOT/backend" && python -m pytest -m "not integration" -q -p no:cacheprovider
verify: cd "$BV_ROOT" && python -m autopep8 --recursive --aggressive --aggressive --max-line-length=127 --exit-code --diff backend/ scrapper/ common/
verify: cd "$BV_ROOT" && python -m flake8 . --count --select=E9,F63,F7,F82 --exclude=.venv,.agent,.git,__pycache__,bharatverse_app,scripts
commit: feat: add LikeService for article likes
---

# TASK-004: Add LikeService, the data layer for article likes

## Why

Likes are the next unbuilt roadmap phase. `design.md` section 2.4 defines the service: `like_article`, `unlike_article`,
`is_liked`, `get_user_likes` returning full articles, and `get_article_like_count`. The `likes` table, its unique index,
and its row-level security policies already exist in `schema.sql` and need no change. This task adds only the Python
service. The HTTP endpoints are TASK-005.

## Security constraint

Writes go through `get_supabase().get_admin_client()`, which uses the service-role key and bypasses row-level
security entirely. The table's policies restricting a user to their own rows are therefore not in force on this path.
Every per-user query in this service must filter on `user_id`. A missing filter would let one user read or delete
another user's likes. The tests assert the real `user_id=eq...` parameter on the wire for exactly this reason.

## Two things confirmed offline that shape the code

- **Counting.** postgrest-py reports a count of 0 for any response with an empty body, and a real HEAD response has
  no body. So `head=True` would silently return 0 in production. The service counts with a normal GET and
  `limit(0)`, which returns an empty list plus the total in the `Content-Range` header.
- **Liked articles.** `articles(*)` in the select embeds each liked article's row through the foreign key, so one
  query returns the likes with their article rows. The service then reads each article's content from storage with
  the existing `ArticleService.load_article`, the same way search does.

## Read first, and nothing else

- `backend/tests/wire.py` (created by TASK-001; you only need to know it exists)

## Steps

### Step 1. Create the service

Create `backend/services/like_service.py` with exactly this content:

<!-- step: create backend/services/like_service.py -->
```python
"""
Article likes, backed by the `likes` table in Supabase Postgres.

These calls use the service-role client, which bypasses row-level security.
That makes filtering by user_id in every per-user query mandatory, not
optional -- the table's RLS policies are not in force on this path.
"""

import logging

from postgrest.exceptions import APIError

from backend.database import get_supabase
from backend.services.article_service import ArticleService
from common.models import Article

logger = logging.getLogger(__name__)

# Postgres SQLSTATE for a foreign-key violation.
_FOREIGN_KEY_VIOLATION = "23503"


class ArticleNotFoundError(Exception):
    """Raised when liking an article id that does not exist."""


class LikeService:
    """Creates, removes, and reads a user's article likes."""

    def __init__(self):
        self.article_service = ArticleService()

    async def like_article(self, user_id: str, article_id: str) -> None:
        """Record a like. Idempotent -- liking twice is not an error.

        The (user_id, article_id) unique index makes the second insert a
        conflict; on_conflict turns that into a no-op update instead of a
        failure. Raises ArticleNotFoundError if the article does not exist.
        """
        client = get_supabase().get_admin_client()
        try:
            client.table("likes").upsert(
                {"user_id": user_id, "article_id": article_id},
                on_conflict="user_id,article_id",
            ).execute()
        except APIError as e:
            # likes.article_id is a foreign key to articles.id. Only that
            # specific violation means "no such article"; a violation on the
            # user side, or any other database error, must not be disguised.
            if e.code == _FOREIGN_KEY_VIOLATION and '"articles"' in (e.details or ""):
                raise ArticleNotFoundError(article_id) from e
            raise
        logger.info(f"User {user_id} liked article {article_id}")

    async def unlike_article(self, user_id: str, article_id: str) -> None:
        """Remove a like. Idempotent -- unliking something not liked is not an error."""
        client = get_supabase().get_admin_client()
        client.table("likes").delete().eq("user_id", user_id).eq("article_id", article_id).execute()
        logger.info(f"User {user_id} unliked article {article_id}")

    async def is_liked(self, user_id: str, article_id: str) -> bool:
        """Whether this user has liked this article."""
        client = get_supabase().get_admin_client()
        response = (
            client.table("likes")
            .select("article_id")
            .eq("user_id", user_id)
            .eq("article_id", article_id)
            .limit(1)
            .execute()
        )
        return bool(response.data)

    async def get_user_likes(self, user_id: str, limit: int = 20) -> list[Article]:
        """Full articles this user has liked, most recently liked first."""
        client = get_supabase().get_admin_client()
        # articles(*) embeds each liked article's row through the foreign key,
        # so this is one query for the rows plus one storage read per article.
        response = (
            client.table("likes")
            .select("created_at", "articles(*)")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return [self.article_service.load_article(client, row["articles"]) for row in response.data]

    async def get_article_like_count(self, article_id: str) -> int:
        """How many users have liked this article."""
        client = get_supabase().get_admin_client()
        # limit(0) returns no rows, only the total in the Content-Range header. A HEAD request
        # (head=True) looks tidier, but postgrest-py reports count=0 for any response with an
        # empty body, which is what a real HEAD response is.
        response = client.table("likes").select("id", count="exact").eq("article_id", article_id).limit(0).execute()
        return response.count or 0
```

### Step 2. Create the tests

Create `backend/tests/test_services/test_like_service.py` with exactly this content:

<!-- step: create backend/tests/test_services/test_like_service.py -->
```python
"""
Unit tests for LikeService.

LikeService uses the service-role client, which bypasses row-level security,
so the only thing keeping one user out of another's likes is the user_id
filter in each query. These tests therefore drive the real service through a
real postgrest query builder (see backend/tests/wire.py) and assert on the
HTTP request that would be sent, not on a mock's call list.
"""

import json
from unittest.mock import MagicMock, patch

import httpx
import pytest
from postgrest.exceptions import APIError

from backend.services.like_service import ArticleNotFoundError, LikeService
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


def use_wire(mock_get_supabase, handler):
    """Route LikeService's admin client to a WireClient and return it."""
    wire = WireClient(handler)
    mock_get_supabase.return_value.get_admin_client.return_value = wire
    return wire


class TestLikeArticle:
    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_upserts_row_with_conflict_target(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, lambda request: httpx.Response(201, json=[]))

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
        use_wire(mock_get_supabase, lambda request: httpx.Response(409, json=error))

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
        use_wire(mock_get_supabase, lambda request: httpx.Response(409, json=error))

        with pytest.raises(APIError):
            await LikeService().like_article("user-x", "art_1")

    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_other_database_errors_propagate(self, mock_get_supabase):
        error = {"code": "42501", "message": "permission denied", "details": None, "hint": None}
        use_wire(mock_get_supabase, lambda request: httpx.Response(403, json=error))

        with pytest.raises(APIError):
            await LikeService().like_article("user-1", "art_1")


class TestUnlikeArticle:
    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_deletes_only_this_users_row_for_this_article(self, mock_get_supabase):
        wire = use_wire(mock_get_supabase, lambda request: httpx.Response(204))

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
        wire = use_wire(mock_get_supabase, lambda request: httpx.Response(200, json=[{"article_id": "art_1"}]))

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
        use_wire(mock_get_supabase, lambda request: httpx.Response(200, json=[]))

        assert await LikeService().is_liked("user-1", "art_1") is False


class TestGetUserLikes:
    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_returns_full_articles_most_recent_first_scoped_to_the_user(self, mock_get_supabase):
        rows = [
            {"created_at": "2026-07-05T00:00:00Z", "articles": make_row("art_2", "Second")},
            {"created_at": "2026-07-04T00:00:00Z", "articles": make_row("art_1", "First")},
        ]
        wire = use_wire(mock_get_supabase, lambda request: httpx.Response(200, json=rows))
        wire.storage = MagicMock()
        wire.storage.from_.return_value.download.return_value = make_blob()

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
        wire = use_wire(mock_get_supabase, lambda request: httpx.Response(200, json=[]))

        await LikeService().get_user_likes("user-1", limit=5)

        assert wire.requests[0].url.params["limit"] == "5"

    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_empty_when_no_likes(self, mock_get_supabase):
        use_wire(mock_get_supabase, lambda request: httpx.Response(200, json=[]))

        assert await LikeService().get_user_likes("user-1") == []


class TestGetArticleLikeCount:
    @pytest.mark.asyncio
    @patch("backend.services.like_service.get_supabase")
    async def test_reads_the_total_from_a_count_only_request(self, mock_get_supabase):
        # With limit(0) PostgREST returns an empty list and the total in Content-Range.
        wire = use_wire(mock_get_supabase, lambda request: httpx.Response(200, json=[], headers={"content-range": "*/7"}))

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
        use_wire(mock_get_supabase, lambda request: httpx.Response(200, json=[]))

        assert await LikeService().get_article_like_count("art_1") == 0
```

## Verify

Run every `verify:` command from the front matter, from the repository root, and make each one exit 0.
If the formatting check prints a diff, run `python -m autopep8 --in-place --aggressive --aggressive
--max-line-length=127 <each file you changed>` and run the check again. Do not edit any file that is not listed
under `allowed`.

## Definition of done

- Every step above was applied exactly as written.
- Every `verify:` command exits 0.
- Only files listed under `allowed` changed.
- You did not run git commit, checkout, reset, or push. The runner commits.

## Out of scope

Do not create the HTTP endpoints (TASK-005). Do not modify `schema.sql` or `deps.py`. Do not join like counts into
article responses. Do not try to reach a live Supabase project.
