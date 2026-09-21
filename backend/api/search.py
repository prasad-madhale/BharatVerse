"""Full-text article search. Autocomplete and semantic search are deferred (see roadmap.md)."""

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
