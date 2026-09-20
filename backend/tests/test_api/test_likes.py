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
