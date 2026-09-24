"""
Unit tests for ArticleService.

Tests save/retrieve logic with a mocked Supabase client (no live network
calls). Live end-to-end verification against a real Supabase project is a
separate, pending step (see roadmap.md) -- the paused project used for
development means the actual storage/table API shapes used here have not
yet been confirmed against the real Supabase Python SDK.
"""

import json
from datetime import date, datetime, timezone

import pytest
from unittest.mock import MagicMock, patch

from backend.services.article_service import ArticleService
from common.models import Article, ArticleImage, Citation, Section


def make_article(article_id="art_20260703_001"):
    return Article(
        id=article_id,
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
        tags=["mauryan-empire", "ancient-india"],
    )


@pytest.fixture
def mock_settings():
    settings = MagicMock()
    settings.articles_storage_bucket = "articles"
    return settings


@pytest.fixture
def mock_supabase_client():
    """A MagicMock standing in for a Supabase Client, with table()/storage chains."""
    client = MagicMock()
    return client


class TestSaveArticle:
    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_uploads_content_and_upserts_metadata(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_admin_client.return_value = mock_supabase_client

        service = ArticleService()
        article = make_article()
        result = await service.save_article(article)

        assert result is article

        # Storage upload called with the right bucket and path
        mock_supabase_client.storage.from_.assert_called_with("articles")
        upload_call = mock_supabase_client.storage.from_.return_value.upload
        upload_call.assert_called_once()
        path_arg, body_arg = upload_call.call_args.args[0], upload_call.call_args.args[1]
        assert path_arg == "articles/2026-07-03/art_20260703_001.json"
        blob = json.loads(body_arg)
        assert blob["content"] == article.content
        assert blob["sections"][0]["heading"] == "Origins"
        assert blob["citations"][0]["source_url"] == article.citations[0].source_url

        # Postgres upsert called with metadata-only row (no content/sections/citations)
        mock_supabase_client.table.assert_called_with("articles")
        upsert_call = mock_supabase_client.table.return_value.upsert
        upsert_call.assert_called_once()
        row = upsert_call.call_args.args[0]
        assert row["id"] == "art_20260703_001"
        assert row["title"] == article.title
        assert row["date"] == "2026-07-03"
        assert row["content_file_path"] == "articles/2026-07-03/art_20260703_001.json"
        assert "content" not in row
        assert "sections" not in row
        assert "created_at" not in row
        assert "updated_at" not in row

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_uploads_images_in_content_blob(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_admin_client.return_value = mock_supabase_client

        article = make_article()
        article.images = [ArticleImage(
            url="https://storage.example/art_20260703_001/0.jpg",
            alt_text="Ruins of a Mauryan-era stupa",
            caption="The Great Stupa",
            credit="Jane Doe via Wikimedia Commons",
            source_url="https://commons.wikimedia.org/wiki/File:Stupa.jpg",
            license="CC BY-SA 4.0",
            width=1200, height=800,
        )]
        article.image_url = article.images[0].url

        await ArticleService().save_article(article)

        upload_call = mock_supabase_client.storage.from_.return_value.upload
        blob = json.loads(upload_call.call_args.args[1])
        assert blob["images"][0]["url"] == article.images[0].url
        assert blob["images"][0]["license"] == "CC BY-SA 4.0"

        row = mock_supabase_client.table.return_value.upsert.call_args.args[0]
        assert row["image_url"] == article.images[0].url


class TestGetArticleById:
    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_returns_none_when_not_found(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        mock_supabase_client.table.return_value.select.return_value.eq.return_value.execute.return_value.data = []

        service = ArticleService()
        result = await service.get_article_by_id("art_missing")

        assert result is None

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_reassembles_article_from_row_and_storage_blob(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client

        row = {
            "id": "art_20260703_001",
            "title": "The Mauryan Empire",
            "summary": "A summary.",
            "date": "2026-07-03",
            "reading_time_minutes": 13,
            "author": "BharatVerse AI",
            "tags": ["mauryan-empire"],
            "image_url": None,
            "content_file_path": "articles/2026-07-03/art_20260703_001.json",
            "created_at": "2026-07-03T00:00:00Z",
            "updated_at": "2026-07-03T00:00:00Z",
        }
        mock_supabase_client.table.return_value.select.return_value.eq.return_value.execute.return_value.data = [row]

        blob = {
            "content": "## Origins\n\nSome content.",
            "sections": [{"heading": "Origins", "content": "Some content.", "order": 1}],
            "citations": [{
                "text": "Maurya Empire",
                "source_url": "https://en.wikipedia.org/wiki/Maurya_Empire",
                "source_name": "wikipedia",
                "accessed_date": "2026-07-03T00:00:00Z",
            }],
        }
        mock_supabase_client.storage.from_.return_value.download.return_value = json.dumps(blob).encode("utf-8")

        service = ArticleService()
        result = await service.get_article_by_id("art_20260703_001")

        assert result is not None
        assert result.id == "art_20260703_001"
        assert result.content == blob["content"]
        assert result.sections[0].heading == "Origins"
        assert result.citations[0].source_url == "https://en.wikipedia.org/wiki/Maurya_Empire"
        assert result.publication_date == date(2026, 7, 3)
        mock_supabase_client.storage.from_.return_value.download.assert_called_once_with(
            "articles/2026-07-03/art_20260703_001.json"
        )
        assert result.images == []  # the blob above has no "images" key -- an older article

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_reassembles_images_from_blob(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client

        row = {
            "id": "art_20260703_001", "title": "The Mauryan Empire", "summary": "A summary.",
            "date": "2026-07-03", "reading_time_minutes": 13, "author": "BharatVerse AI",
            "tags": [], "image_url": "https://storage.example/0.jpg",
            "content_file_path": "articles/2026-07-03/art_20260703_001.json",
            "created_at": "2026-07-03T00:00:00Z", "updated_at": "2026-07-03T00:00:00Z",
        }
        mock_supabase_client.table.return_value.select.return_value.eq.return_value.execute.return_value.data = [row]
        blob = {
            "content": "...", "sections": [], "citations": [],
            "images": [{
                "url": "https://storage.example/0.jpg", "alt_text": "The Great Stupa",
                "caption": None, "credit": "Jane Doe via Wikimedia Commons",
                "source_url": "https://commons.wikimedia.org/wiki/File:Stupa.jpg",
                "license": "CC BY-SA 4.0", "width": 1200, "height": 800,
            }],
        }
        mock_supabase_client.storage.from_.return_value.download.return_value = json.dumps(blob).encode("utf-8")

        result = await ArticleService().get_article_by_id("art_20260703_001")

        assert result.images[0].license == "CC BY-SA 4.0"
        assert result.images[0].credit == "Jane Doe via Wikimedia Commons"


class TestListRecentTitles:
    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_returns_titles_in_response_order(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        query = mock_supabase_client.table.return_value.select.return_value.order.return_value.limit.return_value
        query.execute.return_value.data = [{"title": "Battle of Plassey"}, {"title": "Rani Lakshmibai"}]

        service = ArticleService()
        titles = await service.list_recent_titles()

        assert titles == ["Battle of Plassey", "Rani Lakshmibai"]

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_passes_limit_and_orders_by_date_descending(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        query = mock_supabase_client.table.return_value.select.return_value.order.return_value.limit.return_value
        query.execute.return_value.data = []

        service = ArticleService()
        await service.list_recent_titles(limit=50)

        mock_supabase_client.table.return_value.select.return_value.order.assert_called_once_with(
            "date", desc=True
        )
        mock_supabase_client.table.return_value.select.return_value.order.return_value.limit.assert_called_once_with(
            50
        )

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_returns_empty_list_when_no_articles(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        query = mock_supabase_client.table.return_value.select.return_value.order.return_value.limit.return_value
        query.execute.return_value.data = []

        service = ArticleService()
        titles = await service.list_recent_titles()

        assert titles == []


class TestListIdsMissingImages:
    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_returns_ids_with_no_image_url(
        self, mock_get_settings, mock_get_supabase, mock_settings, mock_supabase_client
    ):
        mock_get_settings.return_value = mock_settings
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        query = mock_supabase_client.table.return_value.select.return_value.is_.return_value
        query.execute.return_value.data = [{"id": "art_1"}, {"id": "art_2"}]

        ids = await ArticleService().list_ids_missing_images()

        mock_supabase_client.table.return_value.select.return_value.is_.assert_called_with("image_url", "null")
        assert ids == ["art_1", "art_2"]
