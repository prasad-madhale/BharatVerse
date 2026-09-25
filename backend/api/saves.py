"""Saved-article (bookmark) endpoints; every route requires a Supabase session."""

from fastapi import APIRouter, Depends, HTTPException, Query
from gotrue.types import User

from backend.api.deps import get_current_user
from backend.services.save_service import ArticleNotFoundError, SaveService
from common.models import Article

router = APIRouter(tags=["saves"])


@router.post("/articles/{article_id}/save", status_code=204)
async def save_article(article_id: str, user: User = Depends(get_current_user)) -> None:
    """Save (bookmark) an article. Idempotent, so a repeated call is still a 204."""
    try:
        await SaveService().save_article(user.id, article_id)
    except ArticleNotFoundError as e:
        raise HTTPException(status_code=404, detail=f"Article '{article_id}' not found") from e


@router.delete("/articles/{article_id}/save", status_code=204)
async def unsave_article(article_id: str, user: User = Depends(get_current_user)) -> None:
    """Remove a save. Idempotent, so unsaving twice is still a 204."""
    await SaveService().unsave_article(user.id, article_id)


@router.get("/users/me/saves", response_model=list[Article])
async def get_saved_articles(
    limit: int = Query(default=20, ge=1, le=50),
    user: User = Depends(get_current_user),
) -> list[Article]:
    """Articles this user has saved, most recently saved first."""
    return await SaveService().get_user_saves(user.id, limit=limit)
