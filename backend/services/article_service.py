"""
Article storage and retrieval, backed by Supabase: metadata in the
`articles` Postgres table, full content (body/sections/citations) as a
JSON file in Supabase Storage referenced by content_file_path.
"""

import hashlib
import json
import logging
from datetime import date as date_type

from backend.config import get_settings
from backend.database import get_supabase
from backend.models.article import ArticleRecord
from common.models import Article, ArticleImage, Citation, Section

logger = logging.getLogger(__name__)


class ArticleService:
    """Saves and retrieves Articles using Supabase Postgres + Storage."""

    def __init__(self):
        self.settings = get_settings()

    async def save_article(self, article: Article) -> Article:
        """
        Persist an article: full content to Supabase Storage, metadata to Postgres. Re-saving an article with the same
        id replaces both.

        Each version of the content goes to a new file named by its own hash; the row is pointed at it, and only then is
        the previous file deleted. A failure part way leaves the row on its previous, intact file -- never on content it
        doesn't match, which is how a failed reprocess once left Mohenjo-daro without its images -- and a new name per
        version means a CDN can never serve the previous content in its place.
        """
        client = get_supabase().get_admin_client()
        bucket = client.storage.from_(self.settings.articles_storage_bucket)
        content = json.dumps({
            "content": article.content,
            "sections": [s.model_dump(mode="json") for s in article.sections],
            "citations": [c.model_dump(mode="json") for c in article.citations],
            "images": [i.model_dump(mode="json") for i in article.images],
        }).encode("utf-8")
        content_path = self._content_file_path(article.id, article.publication_date, content)
        previous = client.table("articles").select("content_file_path").eq("id", article.id).execute().data
        previous_path = previous[0]["content_file_path"] if previous else None

        bucket.upload(content_path, content, file_options={"content-type": "application/json", "upsert": "true"})
        record = self._record_from_article(article, content_path)
        client.table("articles").upsert(
            record.model_dump(mode="json", exclude={"created_at", "updated_at"})
        ).execute()

        if previous_path and previous_path != content_path:
            try:
                bucket.remove([previous_path])
            except Exception:
                logger.warning(f"Saved {article.id} but could not delete its previous content {previous_path}", exc_info=True)

        logger.info(f"Saved article {article.id}")
        return article

    async def get_article_by_id(self, article_id: str, include_unpublished: bool = False) -> Article | None:
        """
        Retrieve a full article (metadata + content) by id, or None if not found. The public key finds only a live
        article; `include_unpublished`, for the pipeline, also finds a scheduled or withdrawn one.
        """
        client = self._reader(include_unpublished)
        response = client.table("articles").select("*").eq("id", article_id).execute()
        if not response.data:
            return None
        return self.load_article(client, response.data[0])

    async def list_recent_titles(self, limit: int = 200) -> list[str]:
        """
        Titles of the most recent articles, most recent first: scheduled and withdrawn ones too.

        Used by the topic generator to avoid proposing a topic that
        duplicates something already written.
        """
        client = get_supabase().get_admin_client()
        response = (
            client.table("articles")
            .select("title")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        return [row["title"] for row in response.data]

    async def list_ids_missing_images(self) -> list[str]:
        """Ids of articles with no featured image, scheduled ones too -- used by backfill_images.py."""
        client = get_supabase().get_admin_client()
        response = client.table("articles").select("id").is_("image_url", "null").execute()
        return [row["id"] for row in response.data]

    async def list_recent_articles(
        self, limit: int = 5, offset: int = 0, include_unpublished: bool = False
    ) -> list[Article]:
        """
        Full, recently-published articles (metadata + content), most recent first. `offset` pages through them, and
        `include_unpublished`, for the pipeline, takes in scheduled and withdrawn ones too.
        """
        client = self._reader(include_unpublished)
        response = (
            client.table("articles")
            .select("*")
            .order("date", desc=True)
            .order("created_at", desc=True)
            .order("id", desc=True)  # a total order, so no page repeats or skips an article
            .range(offset, offset + limit - 1)
            .execute()
        )
        return [self.load_article(client, row) for row in response.data]

    async def get_daily_article(self) -> Article | None:
        """
        Retrieve the current daily article.

        Phase 0: the most recently published article by date (ties broken by
        created_at). Real daily-selection logic (one designated article per
        calendar day, topic uniqueness) is a Phase 4 (scheduler) concern.
        """
        client = get_supabase().get_client()
        response = (
            client.table("articles")
            .select("*")
            .order("date", desc=True)
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
        if not response.data:
            return None
        return self.load_article(client, response.data[0])

    async def list_schedule(self, start: date_type) -> list[dict]:
        """The id, date and status of every article dated `start` or later, earliest first: the days already taken."""
        client = get_supabase().get_admin_client()
        response = (
            client.table("articles")
            .select("id,date,status")
            .gte("date", start.isoformat())
            .order("date")
            .order("id")
            .execute()
        )
        return [{**row, "date": date_type.fromisoformat(row["date"])} for row in response.data]

    @staticmethod
    def _reader(include_unpublished: bool):
        """The public key, which row-level security limits to live articles, or the service role, which sees them all."""
        supabase = get_supabase()
        return supabase.get_admin_client() if include_unpublished else supabase.get_client()

    def _record_from_article(self, article: Article, content_file_path: str) -> ArticleRecord:
        return ArticleRecord(
            id=article.id,
            title=article.title,
            summary=article.summary,
            date=article.publication_date,
            reading_time_minutes=article.reading_time_minutes,
            author=article.author,
            tags=article.tags,
            era=article.era,
            image_url=article.image_url,
            content_file_path=content_file_path,
        )

    def _content_file_path(self, article_id: str, publication_date: date_type, content: bytes) -> str:
        return f"articles/{publication_date.isoformat()}/{article_id}-{hashlib.sha256(content).hexdigest()[:12]}.json"

    def load_article(self, client, row: dict) -> Article:
        """Reassemble an Article from its Postgres row and Storage content blob."""
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
            images=[ArticleImage(**i) for i in blob.get("images", [])],
            publication_date=record.date,
            reading_time_minutes=record.reading_time_minutes,
            author=record.author,
            tags=record.tags,
            era=record.era,
            image_url=record.image_url,
            created_at=record.created_at,
            updated_at=record.updated_at,
        )
