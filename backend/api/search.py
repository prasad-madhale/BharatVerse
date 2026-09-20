"""
Search endpoint.

Phase 2 scope: full-text search only (title/summary via Postgres FTS).
Autocomplete and semantic search are deferred -- see roadmap.md.

Mounted at /articles/search, per design.md. main.py must register this router
before the articles router, whose /articles/{article_id} route would otherwise
capture the request and treat "search" as an article id.
"""

from fastapi import APIRouter, Query

from backend.services.search_service import SearchService
from common.models import Article

router = APIRouter(prefix="/articles/search", tags=["search"])


@router.get("", response_model=list[Article])
async def search_articles(
    q: str = Query(..., min_length=1),
    limit: int = Query(default=20, ge=1, le=50),
) -> list[Article]:
    """Full-text search articles by title/summary, most recent match first."""
    return await SearchService().search_articles(q, limit=limit)
