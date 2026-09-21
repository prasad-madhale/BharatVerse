"""Full-text article search and autocomplete. Semantic search is deferred (see roadmap.md)."""

from fastapi import APIRouter, Query

from backend.services.search_service import SearchService
from common.models import Article

router = APIRouter(prefix="/articles/search", tags=["search"])


@router.get("", response_model=list[Article])
async def search_articles(
    q: str = Query(..., min_length=1),
    limit: int = Query(default=20, ge=1, le=50),
) -> list[Article]:
    """Full-text search articles by title, tags and summary, most relevant first."""
    return await SearchService().search_articles(q, limit=limit)


@router.get("/autocomplete", response_model=list[str])
async def autocomplete(
    q: str = Query(..., min_length=1, max_length=100),
    limit: int = Query(default=10, ge=1, le=20),
) -> list[str]:
    """Search suggestions: the titles and tags that start with what was typed, the most shared first."""
    return await SearchService().autocomplete(q, limit=limit)
