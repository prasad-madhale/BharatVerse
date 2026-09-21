"""Full-text search over article title/summary, ranked by relevance (autocomplete and semantic search are deferred)."""

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
        Articles matching `query` (websearch syntax: quoted phrases, -exclude), most relevant first.

        Ranking lives in the search_articles SQL function (schema.sql), which a PostgREST filter cannot express.
        """
        client = get_supabase().get_client()
        response = client.rpc("search_articles", {"search_query": query, "match_limit": limit}).execute()
        return [self.article_service.load_article(client, row) for row in response.data]
