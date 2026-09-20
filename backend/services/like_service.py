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
