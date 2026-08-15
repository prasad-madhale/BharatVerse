"""
Full-text search over articles' title/summary, backed by Postgres FTS via
Supabase PostgREST's text_search().

Phase 2 scope is FTS only -- autocomplete (search_suggestions) and semantic
search (pgvector) are deferred; see roadmap.md's open product question on
whether to scope those out of MVP entirely.
"""

import logging

from backend.database import get_supabase
from backend.services.article_service import ArticleService
from common.models import Article

logger = logging.getLogger(__name__)


class SearchService:
    """Searches published articles by title/summary using Postgres full-text search."""

    def __init__(self):
        self.article_service = ArticleService()

    async def search_articles(self, query: str, limit: int = 20) -> list[Article]:
        """
        Full-text search articles' title/summary for `query`, most recent
        match first.

        Uses `websearch_to_tsquery` semantics (quoted phrases, `-exclude`,
        implicit AND between terms) via the `search_vector` generated
        column. Ordered by publication date rather than text-match rank --
        relevance ranking would need a Postgres RPC function, out of scope
        for this FTS-only pass.
        """
        client = get_supabase().get_client()
        response = (
            client.table("articles")
            .select("*")
            .text_search("search_vector", query, options={"type": "websearch", "config": "english"})
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        return [self.article_service.load_article(client, row) for row in response.data]
