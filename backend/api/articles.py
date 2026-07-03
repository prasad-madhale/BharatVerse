"""
Article endpoints.

Phase 0: just enough to serve one real article end-to-end. Pagination,
search, and the semantic/autocomplete endpoints are Phase 2.
"""

from fastapi import APIRouter, HTTPException

from backend.services.article_service import ArticleService
from common.models import Article

router = APIRouter(prefix="/articles", tags=["articles"])


@router.get("/daily", response_model=Article)
async def get_daily_article() -> Article:
    """Get the current daily article."""
    article = await ArticleService().get_daily_article()
    if article is None:
        raise HTTPException(status_code=404, detail="No articles available")
    return article


@router.get("/{article_id}", response_model=Article)
async def get_article(article_id: str) -> Article:
    """Get an article by its id."""
    article = await ArticleService().get_article_by_id(article_id)
    if article is None:
        raise HTTPException(status_code=404, detail=f"Article '{article_id}' not found")
    return article
