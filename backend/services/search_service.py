"""Full-text search over article title/summary via Postgres FTS (autocomplete and semantic search are deferred)."""

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
        Articles matching `query` (websearch syntax: quoted phrases, -exclude), newest first.

        Not ranked by relevance; that would need a Postgres RPC.
        """
        client = get_supabase().get_client()
        # text_search() must come last: its builder only has execute(). "web_search" is postgrest-py's name for
        # the wfts operator; any other type falls back to strict fts, which rejects multi-word queries.
        response = (
            client.table("articles")
            .select("*")
            .order("date", desc=True)
            .limit(limit)
            .text_search("search_vector", query, options={"type": "web_search", "config": "english"})
            .execute()
        )
        return [self.article_service.load_article(client, row) for row in response.data]
