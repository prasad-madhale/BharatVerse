"""
Unit tests for the articles API router.

Uses FastAPI's TestClient with ArticleService mocked out -- no live
Supabase or network calls.
"""

from datetime import date, datetime, timezone
from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

from backend.main import app
from common.models import Article, Section, Citation


def make_article():
    return Article(
        id="art_20260703_001",
        title="The Mauryan Empire",
        summary="A summary.",
        content="## Origins\n\nSome content.",
        sections=[Section(heading="Origins", content="Some content.", order=1)],
        citations=[
            Citation(
                text="Maurya Empire",
                source_url="https://en.wikipedia.org/wiki/Maurya_Empire",
                source_name="wikipedia",
                accessed_date=datetime(2026, 7, 3, tzinfo=timezone.utc),
            )
        ],
        publication_date=date(2026, 7, 3),
        reading_time_minutes=13,
        tags=["mauryan-empire"],
    )


@pytest.fixture
def client():
    return TestClient(app)


class TestGetDailyArticle:
    def test_returns_article_when_available(self, client):
        with patch("backend.api.articles.ArticleService") as mock_service_class:
            mock_service_class.return_value.get_daily_article = AsyncMock(return_value=make_article())

            response = client.get("/api/v1/articles/daily")

        assert response.status_code == 200
        body = response.json()
        assert body["id"] == "art_20260703_001"
        assert body["title"] == "The Mauryan Empire"
        assert body["sections"][0]["heading"] == "Origins"

    def test_returns_404_when_no_articles(self, client):
        with patch("backend.api.articles.ArticleService") as mock_service_class:
            mock_service_class.return_value.get_daily_article = AsyncMock(return_value=None)

            response = client.get("/api/v1/articles/daily")

        assert response.status_code == 404


class TestGetArticleById:
    def test_returns_article_when_found(self, client):
        with patch("backend.api.articles.ArticleService") as mock_service_class:
            mock_service_class.return_value.get_article_by_id = AsyncMock(return_value=make_article())

            response = client.get("/api/v1/articles/art_20260703_001")

        assert response.status_code == 200
        assert response.json()["id"] == "art_20260703_001"

    def test_returns_404_when_not_found(self, client):
        with patch("backend.api.articles.ArticleService") as mock_service_class:
            mock_service_class.return_value.get_article_by_id = AsyncMock(return_value=None)

            response = client.get("/api/v1/articles/art_missing")

        assert response.status_code == 404
        assert "art_missing" in response.json()["detail"]

    def test_daily_route_not_shadowed_by_id_route(self, client):
        """Regression guard: /daily must resolve to the daily endpoint, not
        be captured by /{article_id} with article_id='daily'."""
        with patch("backend.api.articles.ArticleService") as mock_service_class:
            mock_service_class.return_value.get_daily_article = AsyncMock(return_value=make_article())
            mock_service_class.return_value.get_article_by_id = AsyncMock(return_value=None)

            response = client.get("/api/v1/articles/daily")

        assert response.status_code == 200
        mock_service_class.return_value.get_daily_article.assert_called_once()
        mock_service_class.return_value.get_article_by_id.assert_not_called()


class TestHealth:
    def test_health_endpoint(self, client):
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}
