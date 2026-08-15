"""
Unit tests for the search API router.

Uses FastAPI's TestClient with SearchService mocked out -- no live
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


class TestSearchArticles:
    def test_returns_matches_from_service(self, client):
        with patch("backend.api.search.SearchService") as mock_service_class:
            mock_service_class.return_value.search_articles = AsyncMock(return_value=[make_article()])

            response = client.get("/api/v1/search?q=Ashoka")

        assert response.status_code == 200
        body = response.json()
        assert len(body) == 1
        assert body[0]["id"] == "art_20260703_001"

    def test_returns_empty_list_when_no_matches(self, client):
        with patch("backend.api.search.SearchService") as mock_service_class:
            mock_service_class.return_value.search_articles = AsyncMock(return_value=[])

            response = client.get("/api/v1/search?q=nonexistent")

        assert response.status_code == 200
        assert response.json() == []

    def test_passes_query_and_default_limit_through(self, client):
        with patch("backend.api.search.SearchService") as mock_service_class:
            mock_service_class.return_value.search_articles = AsyncMock(return_value=[])

            client.get("/api/v1/search?q=Ashoka")

        mock_service_class.return_value.search_articles.assert_called_once_with("Ashoka", limit=20)

    def test_passes_limit_query_param_through(self, client):
        with patch("backend.api.search.SearchService") as mock_service_class:
            mock_service_class.return_value.search_articles = AsyncMock(return_value=[])

            client.get("/api/v1/search?q=Ashoka&limit=3")

        mock_service_class.return_value.search_articles.assert_called_once_with("Ashoka", limit=3)

    def test_rejects_missing_query(self, client):
        response = client.get("/api/v1/search")

        assert response.status_code == 422

    def test_rejects_empty_query(self, client):
        response = client.get("/api/v1/search?q=")

        assert response.status_code == 422

    def test_rejects_limit_above_max(self, client):
        response = client.get("/api/v1/search?q=Ashoka&limit=51")

        assert response.status_code == 422
