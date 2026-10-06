"""
Unit tests for ArticleService.

Tests save/retrieve logic with a mocked Supabase client (no live network
calls). Live end-to-end verification against a real Supabase project is a
separate, pending step (see roadmap.md) -- the paused project used for
development means the actual storage/table API shapes used here have not
yet been confirmed against the real Supabase Python SDK.
"""

import hashlib
import json
from datetime import date, datetime, timezone

import httpx
import pytest
from unittest.mock import MagicMock, patch

from backend.services.article_service import ArticleService
from backend.tests.wire import use_wire
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


class FakeStore:
    """The admin client's articles table and Storage bucket, recording each step of a save in order."""

    def __init__(self, previous_path=None, fail_upsert=False, fail_remove=False):
        self.steps = []
        self.client = MagicMock()
        bucket = self.client.storage.from_.return_value
        bucket.upload.side_effect = lambda path, body, file_options: self._record("upload", path, body)
        bucket.remove.side_effect = lambda paths: self._record("remove", paths, fail=fail_remove)
        table = self.client.table.return_value
        table.select.return_value.eq.return_value.execute.return_value.data = (
            [{"content_file_path": previous_path}] if previous_path else [])
        table.upsert.side_effect = lambda row: self._upsert(row, fail_upsert)

    def _record(self, step, *args, fail=False):
        self.steps.append((step, *args))
        if fail:
            raise RuntimeError(f"{step} failed")

    def _upsert(self, row, fail):
        self._record("upsert", row, fail=fail)
        return MagicMock()

    def step_names(self):
        return [step[0] for step in self.steps]


@pytest.fixture
def store(mock_settings):
    """save_article against a FakeStore; call it with the FakeStore's options to replace the default."""
    with patch("backend.services.article_service.get_settings", return_value=mock_settings), \
            patch("backend.services.article_service.get_supabase") as mock_get_supabase:
        def use(**options):
            fake = FakeStore(**options)
            mock_get_supabase.return_value.get_admin_client.return_value = fake.client
            return fake
        yield use


class TestSaveArticle:
    @pytest.mark.asyncio
    async def test_writes_the_content_to_a_file_named_by_its_hash_then_points_the_row_at_it(self, store):
        fake = store()
        article = make_article()

        result = await ArticleService().save_article(article)

        assert result is article
        assert fake.step_names() == ["upload", "upsert"]
        _, path, body = fake.steps[0]
        assert path == f"articles/2026-07-03/art_20260703_001-{hashlib.sha256(body).hexdigest()[:12]}.json"
        blob = json.loads(body)
        assert blob["content"] == article.content
        assert blob["sections"][0]["heading"] == "Origins"
        assert blob["citations"][0]["source_url"] == article.citations[0].source_url
        row = fake.steps[1][1]
        assert row["id"] == "art_20260703_001" and row["date"] == "2026-07-03" and row["title"] == article.title
        assert row["content_file_path"] == path
        assert not {"content", "sections", "created_at", "updated_at"} & set(row)

    @pytest.mark.asyncio
    async def test_deletes_the_previous_file_only_after_the_row_points_at_the_new_one(self, store):
        fake = store(previous_path="articles/2026-07-03/art_20260703_001.json")

        await ArticleService().save_article(make_article())

        assert fake.step_names() == ["upload", "upsert", "remove"]
        assert fake.steps[2][1] == ["articles/2026-07-03/art_20260703_001.json"]

    @pytest.mark.asyncio
    async def test_a_failed_row_write_leaves_the_previous_file_in_place(self, store):
        fake = store(previous_path="articles/2026-07-03/art_20260703_001.json", fail_upsert=True)

        with pytest.raises(RuntimeError, match="upsert failed"):
            await ArticleService().save_article(make_article())

        assert "remove" not in fake.step_names()

    @pytest.mark.asyncio
    async def test_saving_unchanged_content_keeps_its_own_file(self, store):
        first = store()
        await ArticleService().save_article(make_article())
        same_path = first.steps[0][1]

        again = store(previous_path=same_path)
        await ArticleService().save_article(make_article())

        assert again.step_names() == ["upload", "upsert"]
        assert again.steps[0][1] == same_path

    @pytest.mark.asyncio
    async def test_a_failed_delete_of_the_previous_file_does_not_fail_the_save(self, store, caplog):
        store(previous_path="articles/2026-07-03/old.json", fail_remove=True)

        result = await ArticleService().save_article(make_article())

        assert result.id == "art_20260703_001"
        assert "could not delete its previous content articles/2026-07-03/old.json" in caplog.text

    @pytest.mark.asyncio
    async def test_the_images_travel_in_the_content_and_the_first_on_the_row(self, store):
        fake = store()
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

        blob = json.loads(fake.steps[0][2])
        assert blob["images"][0]["url"] == article.images[0].url
        assert blob["images"][0]["license"] == "CC BY-SA 4.0"
        assert fake.steps[1][1]["image_url"] == article.images[0].url


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
        mock_get_supabase.return_value.get_admin_client.return_value = mock_supabase_client
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
        mock_get_supabase.return_value.get_admin_client.return_value = mock_supabase_client
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
        mock_get_supabase.return_value.get_admin_client.return_value = mock_supabase_client
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
        mock_get_supabase.return_value.get_admin_client.return_value = mock_supabase_client
        query = mock_supabase_client.table.return_value.select.return_value.is_.return_value
        query.execute.return_value.data = [{"id": "art_1"}, {"id": "art_2"}]

        ids = await ArticleService().list_ids_missing_images()

        mock_supabase_client.table.return_value.select.return_value.is_.assert_called_with("image_url", "null")
        assert ids == ["art_1", "art_2"]


class TestPublicAndPipelineReads:
    """The public key sees what row-level security lets through (live articles); the pipeline sees everything."""

    @pytest.mark.asyncio
    @pytest.mark.parametrize("include_unpublished, client", [(False, "get_client"), (True, "get_admin_client")])
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_get_article_by_id(self, mock_get_settings, mock_get_supabase, mock_settings,
                                     include_unpublished, client):
        mock_get_settings.return_value = mock_settings
        wire = use_wire(mock_get_supabase, lambda request: httpx.Response(200, json=[]),
                        admin=include_unpublished)

        assert await ArticleService().get_article_by_id("art_1", include_unpublished=include_unpublished) is None

        (request,) = wire.requests
        assert request.url.params["id"] == "eq.art_1"
        getattr(mock_get_supabase.return_value, client).assert_called_once()

    @pytest.mark.asyncio
    @pytest.mark.parametrize("include_unpublished", [False, True])
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_list_recent_articles(self, mock_get_settings, mock_get_supabase, mock_settings,
                                        include_unpublished):
        mock_get_settings.return_value = mock_settings
        wire = use_wire(mock_get_supabase, lambda request: httpx.Response(200, json=[]),
                        admin=include_unpublished)

        await ArticleService().list_recent_articles(limit=100, include_unpublished=include_unpublished)

        assert len(wire.requests) == 1


class TestListSchedule:
    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    @patch("backend.services.article_service.get_settings")
    async def test_lists_every_article_from_a_day_on_with_the_service_role(
        self, mock_get_settings, mock_get_supabase, mock_settings
    ):
        mock_get_settings.return_value = mock_settings
        wire = use_wire(mock_get_supabase, lambda request: httpx.Response(200, json=[
            {"id": "art_20261006_001", "date": "2026-10-06", "status": "published"},
            {"id": "art_20261007_001", "date": "2026-10-07", "status": "withdrawn"},
        ]), admin=True)

        schedule = await ArticleService().list_schedule(date(2026, 10, 6))

        assert schedule == [
            {"id": "art_20261006_001", "date": date(2026, 10, 6), "status": "published"},
            {"id": "art_20261007_001", "date": date(2026, 10, 7), "status": "withdrawn"},
        ]
        (request,) = wire.requests
        assert request.url.params["select"] == "id,date,status"
        assert request.url.params["date"] == "gte.2026-10-06"
        assert request.url.params["order"] == "date,id"
