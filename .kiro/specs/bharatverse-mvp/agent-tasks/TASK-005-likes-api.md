---
id: TASK-005
title: Expose likes over HTTP at the paths the design doc specifies
depends_on: TASK-004
requires: 
allowed: backend/api/likes.py, backend/main.py, backend/tests/test_api/test_likes.py
verify: cd "$BV_ROOT/backend" && python -m pytest tests/test_api/test_likes.py -q --no-cov -p no:cacheprovider
verify: cd "$BV_ROOT/backend" && python -m pytest -m "not integration" -q -p no:cacheprovider
verify: cd "$BV_ROOT" && python -m autopep8 --recursive --aggressive --aggressive --max-line-length=127 --exit-code --diff backend/ scrapper/ common/
verify: cd "$BV_ROOT" && python -m flake8 . --count --select=E9,F63,F7,F82 --exclude=.venv,.agent,.git,__pycache__,bharatverse_app,scripts
verify: cd "$BV_ROOT" && grep -q 'likes_router' backend/main.py
verify: cd "$BV_ROOT" && grep -q '/users/me/likes' backend/api/likes.py
commit: feat: add authenticated likes endpoints
---

# TASK-005: Expose likes over HTTP at the paths the design doc specifies

## Why

TASK-004 added the data layer. This task puts it behind three authenticated endpoints, at the paths `design.md`
section 2.5 specifies: `POST` and `DELETE /api/v1/articles/{id}/like`, and `GET /api/v1/users/me/likes`, which
returns the user's liked articles. It is the first real consumer of `backend/api/deps.py`'s `get_current_user`,
which has been built and tested but unused since the auth phase.

The user id always comes from the verified token, never from the path, query, or body. Liking an article id that does
not exist returns 404 instead of a 500 from the database.

## Read first, and nothing else

- `backend/main.py`

## Steps

### Step 1. Create the router

Create `backend/api/likes.py` with exactly this content:

<!-- step: create backend/api/likes.py -->
```python
"""
Article like endpoints.

Every route here requires a valid Supabase session. The user id comes from
the verified token via get_current_user, never from the request body, so a
caller cannot act on someone else's behalf. Paths follow design.md:
POST/DELETE /articles/{id}/like and GET /users/me/likes.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from gotrue.types import User

from backend.api.deps import get_current_user
from backend.services.like_service import ArticleNotFoundError, LikeService
from common.models import Article

router = APIRouter(tags=["likes"])


@router.post("/articles/{article_id}/like", status_code=204)
async def like_article(article_id: str, user: User = Depends(get_current_user)) -> None:
    """Like an article. Idempotent, so a repeated call is still a 204."""
    try:
        await LikeService().like_article(user.id, article_id)
    except ArticleNotFoundError as e:
        raise HTTPException(status_code=404, detail=f"Article '{article_id}' not found") from e


@router.delete("/articles/{article_id}/like", status_code=204)
async def unlike_article(article_id: str, user: User = Depends(get_current_user)) -> None:
    """Remove a like. Idempotent, so unliking twice is still a 204."""
    await LikeService().unlike_article(user.id, article_id)


@router.get("/users/me/likes", response_model=list[Article])
async def get_liked_articles(
    limit: int = Query(default=20, ge=1, le=50),
    user: User = Depends(get_current_user),
) -> list[Article]:
    """Articles this user has liked, most recently liked first."""
    return await LikeService().get_user_likes(user.id, limit=limit)
```

### Step 2. Register the router

Two small edits to `backend/main.py`.

<!-- step: replace backend/main.py -->
Replace this exact text:

```python
from backend.api.auth import router as auth_router
```

with this exact text:

```python
from backend.api.auth import router as auth_router
from backend.api.likes import router as likes_router
```

<!-- step: replace backend/main.py -->
Replace this exact text:

```python
app.include_router(auth_router, prefix=settings.api_prefix)
```

with this exact text:

```python
app.include_router(auth_router, prefix=settings.api_prefix)
app.include_router(likes_router, prefix=settings.api_prefix)
```

### Step 3. Create the tests

Create `backend/tests/test_api/test_likes.py` with exactly this content:

<!-- step: create backend/tests/test_api/test_likes.py -->
```python
"""
Unit tests for the likes API router.

LikeService is mocked and get_current_user is overridden, so no live
Supabase or network calls happen.
"""

from datetime import date
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

from backend.api.deps import get_current_user
from backend.main import app
from backend.services.like_service import ArticleNotFoundError
from common.models import Article

# HTTPBearer answers a missing Authorization header with 403 on the pinned
# FastAPI 0.109 and with 401 on newer releases. Either means "rejected".
REJECTED = (401, 403)


def make_article(article_id="art_20260703_001"):
    return Article(
        id=article_id,
        title="The Mauryan Empire",
        summary="A summary.",
        content="## Origins\n\nSome content.",
        publication_date=date(2026, 7, 3),
        reading_time_minutes=13,
    )


@pytest.fixture
def client():
    """A client whose requests arrive already authenticated as user-123."""
    app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id="user-123")
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture
def anonymous_client():
    """A client with no auth override, so the real dependency runs."""
    app.dependency_overrides.clear()
    return TestClient(app)


class TestRouting:
    def test_like_routes_follow_the_design_doc_paths(self, anonymous_client):
        paths = anonymous_client.get("/openapi.json").json()["paths"]

        assert set(paths["/api/v1/articles/{article_id}/like"]) == {"post", "delete"}
        assert set(paths["/api/v1/users/me/likes"]) == {"get"}

    def test_liking_does_not_shadow_the_article_by_id_route(self, anonymous_client):
        paths = anonymous_client.get("/openapi.json").json()["paths"]

        assert "get" in paths["/api/v1/articles/{article_id}"]


class TestLikeArticle:
    def test_returns_204_and_uses_the_token_users_id(self, client):
        with patch("backend.api.likes.LikeService") as mock_service_class:
            mock_service_class.return_value.like_article = AsyncMock(return_value=None)

            response = client.post("/api/v1/articles/art_1/like")

        assert response.status_code == 204
        mock_service_class.return_value.like_article.assert_called_once_with("user-123", "art_1")

    def test_returns_404_for_an_unknown_article(self, client):
        with patch("backend.api.likes.LikeService") as mock_service_class:
            mock_service_class.return_value.like_article = AsyncMock(
                side_effect=ArticleNotFoundError("art_missing")
            )

            response = client.post("/api/v1/articles/art_missing/like")

        assert response.status_code == 404
        assert "art_missing" in response.json()["detail"]

    def test_rejects_anonymous_caller_without_touching_the_service(self, anonymous_client):
        with patch("backend.api.likes.LikeService") as mock_service_class:
            response = anonymous_client.post("/api/v1/articles/art_1/like")

        assert response.status_code in REJECTED
        mock_service_class.assert_not_called()


class TestUnlikeArticle:
    def test_returns_204_and_uses_the_token_users_id(self, client):
        with patch("backend.api.likes.LikeService") as mock_service_class:
            mock_service_class.return_value.unlike_article = AsyncMock(return_value=None)

            response = client.delete("/api/v1/articles/art_1/like")

        assert response.status_code == 204
        mock_service_class.return_value.unlike_article.assert_called_once_with("user-123", "art_1")

    def test_rejects_anonymous_caller_without_touching_the_service(self, anonymous_client):
        with patch("backend.api.likes.LikeService") as mock_service_class:
            response = anonymous_client.delete("/api/v1/articles/art_1/like")

        assert response.status_code in REJECTED
        mock_service_class.assert_not_called()


class TestGetLikedArticles:
    def test_returns_the_users_liked_articles(self, client):
        with patch("backend.api.likes.LikeService") as mock_service_class:
            mock_service_class.return_value.get_user_likes = AsyncMock(
                return_value=[make_article("art_2"), make_article("art_1")]
            )

            response = client.get("/api/v1/users/me/likes")

        assert response.status_code == 200
        assert [a["id"] for a in response.json()] == ["art_2", "art_1"]
        mock_service_class.return_value.get_user_likes.assert_called_once_with("user-123", limit=20)

    def test_passes_limit_through(self, client):
        with patch("backend.api.likes.LikeService") as mock_service_class:
            mock_service_class.return_value.get_user_likes = AsyncMock(return_value=[])

            client.get("/api/v1/users/me/likes?limit=10")

        mock_service_class.return_value.get_user_likes.assert_called_once_with("user-123", limit=10)

    def test_rejects_limit_above_max(self, client):
        assert client.get("/api/v1/users/me/likes?limit=51").status_code == 422

    def test_rejects_anonymous_caller_without_touching_the_service(self, anonymous_client):
        with patch("backend.api.likes.LikeService") as mock_service_class:
            response = anonymous_client.get("/api/v1/users/me/likes")

        assert response.status_code in REJECTED
        mock_service_class.assert_not_called()
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

Do not add a like count to article responses, do not touch the Flutter app, and do not modify `deps.py` or
`schema.sql`.
