"""Full-text search over article title, tags and summary, and autocomplete suggestions (semantic search is deferred)."""

import logging

from backend.database import get_supabase
from backend.services.article_service import ArticleService
from common.models import Article

logger = logging.getLogger(__name__)


class SearchService:
    """Searches published articles by title, tags and summary using Postgres full-text search, and suggests searches."""

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

    async def autocomplete(self, prefix: str, limit: int = 10) -> list[str]:
        """
        Titles and tags that start with `prefix`, the ones more articles carry first.

        Looked up in the search_suggestions table by the autocomplete_suggestions SQL function (schema.sql); a trigger
        keeps the table in step with the articles.
        """
        if not prefix.strip():
            return []
        client = get_supabase().get_client()
        response = client.rpc("autocomplete_suggestions", {"prefix": prefix, "match_limit": limit}).execute()
        return [row["term"] for row in response.data]
