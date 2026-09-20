"""
Article likes, backed by the `likes` table.

Uses the service-role client, which bypasses row-level security, so every
per-user query must filter by user_id itself.
"""

import logging

from postgrest.exceptions import APIError

from backend.database import get_supabase
from backend.services.article_service import ArticleService
from common.models import Article

logger = logging.getLogger(__name__)

_FOREIGN_KEY_VIOLATION = "23503"  # Postgres SQLSTATE


class ArticleNotFoundError(Exception):
    """Raised when liking an article id that does not exist."""


class LikeService:
    """Creates, removes, and reads a user's article likes."""

    def __init__(self):
        self.article_service = ArticleService()

    async def like_article(self, user_id: str, article_id: str) -> None:
        """Record a like. Idempotent. Raises ArticleNotFoundError if the article does not exist."""
        client = get_supabase().get_admin_client()
        try:
            client.table("likes").upsert(
                {"user_id": user_id, "article_id": article_id},
                on_conflict="user_id,article_id",
            ).execute()
        except APIError as e:
            # Only a foreign-key violation on articles means "no such article"; anything else must surface.
            if e.code == _FOREIGN_KEY_VIOLATION and '"articles"' in (e.details or ""):
                raise ArticleNotFoundError(article_id) from e
            raise
        logger.info(f"User {user_id} liked article {article_id}")

    async def unlike_article(self, user_id: str, article_id: str) -> None:
        """Remove a like. Idempotent."""
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
        # articles(*) embeds each liked article's row through the foreign key.
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
        # limit(0) returns only the total (Content-Range). head=True would look tidier, but postgrest-py
        # reports count=0 for an empty body, which is what a real HEAD response is.
        response = (
            client.table("likes")
            .select("id", count="exact")
            .eq("article_id", article_id)
            .limit(0)
            .execute()
        )
        return response.count or 0
