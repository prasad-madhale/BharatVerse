"""
Article storage and retrieval, backed by Supabase: metadata in the
`articles` Postgres table, full content (body/sections/citations) as a
JSON file in Supabase Storage referenced by content_file_path.

NOTE: the Supabase calls here (storage upload/download, table upsert) are
unit-tested with a mocked client but have not yet been exercised against a
live Supabase project (see backend/tests/test_database/ for the property
test that already validates the Postgres row round-trip). Verify end-to-end
once a live project is available.
"""

import json
import logging
from datetime import date as date_type

from backend.config import get_settings
from backend.database import get_supabase
from backend.models.article import ArticleRecord
from common.models import Article, Citation, Section

logger = logging.getLogger(__name__)


class ArticleService:
    """Saves and retrieves Articles using Supabase Postgres + Storage."""

    def __init__(self):
        self.settings = get_settings()

    async def save_article(self, article: Article) -> Article:
        """
        Persist an article: full content to Supabase Storage, metadata to
        Postgres. Idempotent -- re-saving an article with the same id
        overwrites both the storage file and the Postgres row.
        """
        client = get_supabase().get_admin_client()
        record = self._record_from_article(article)

        content_blob = {
            "content": article.content,
            "sections": [s.model_dump(mode="json") for s in article.sections],
            "citations": [c.model_dump(mode="json") for c in article.citations],
        }
        client.storage.from_(self.settings.articles_storage_bucket).upload(
            record.content_file_path,
            json.dumps(content_blob).encode("utf-8"),
            file_options={"content-type": "application/json", "upsert": "true"},
        )

        client.table("articles").upsert(
            record.model_dump(mode="json", exclude={"created_at", "updated_at"})
        ).execute()

        logger.info(f"Saved article {article.id}")
        return article

    async def get_article_by_id(self, article_id: str) -> Article | None:
        """Retrieve a full article (metadata + content) by id, or None if not found."""
        client = get_supabase().get_client()
        response = client.table("articles").select("*").eq("id", article_id).execute()
        if not response.data:
            return None
        return self._load_article(client, response.data[0])

    async def get_daily_article(self) -> Article | None:
        """
        Retrieve the current daily article.

        Phase 0: the most recently published article by date. Real
        daily-selection logic (one designated article per calendar day,
        topic uniqueness) is a Phase 4 (scheduler) concern.
        """
        client = get_supabase().get_client()
        response = (
            client.table("articles")
            .select("*")
            .order("date", desc=True)
            .limit(1)
            .execute()
        )
        if not response.data:
            return None
        return self._load_article(client, response.data[0])

    def _record_from_article(self, article: Article) -> ArticleRecord:
        return ArticleRecord(
            id=article.id,
            title=article.title,
            summary=article.summary,
            date=article.publication_date,
            reading_time_minutes=article.reading_time_minutes,
            author=article.author,
            tags=article.tags,
            image_url=article.image_url,
            content_file_path=self._content_file_path(article.id, article.publication_date),
        )

    def _content_file_path(self, article_id: str, publication_date: date_type) -> str:
        return f"articles/{publication_date.isoformat()}/{article_id}.json"

    def _load_article(self, client, row: dict) -> Article:
        record = ArticleRecord(**row)
        blob_bytes = client.storage.from_(self.settings.articles_storage_bucket).download(
            record.content_file_path
        )
        blob = json.loads(blob_bytes)

        return Article(
            id=record.id,
            title=record.title,
            summary=record.summary,
            content=blob["content"],
            sections=[Section(**s) for s in blob["sections"]],
            citations=[Citation(**c) for c in blob["citations"]],
            publication_date=record.date,
            reading_time_minutes=record.reading_time_minutes,
            author=record.author,
            tags=record.tags,
            image_url=record.image_url,
            created_at=record.created_at,
            updated_at=record.updated_at,
        )
