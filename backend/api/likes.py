"""Article like endpoints; every route requires a Supabase session."""

from fastapi import APIRouter, Depends, HTTPException, Query
from gotrue.types import User

from backend.api.deps import get_current_user
from backend.services.like_service import ArticleNotFoundError, LikeService
from common.models import Article

router = APIRouter(tags=["likes"])


@router.post("/articles/{article_id}/like", status_code=204)
async def like_article(article_id: str, user: User = Depends(get_current_user)) -> None:
    """Like an article. Idempotent, so a repeated call is still a 204."""
    try:
        await LikeService().like_article(user.id, article_id)
    except ArticleNotFoundError as e:
        raise HTTPException(status_code=404, detail=f"Article '{article_id}' not found") from e


@router.delete("/articles/{article_id}/like", status_code=204)
async def unlike_article(article_id: str, user: User = Depends(get_current_user)) -> None:
    """Remove a like. Idempotent, so unliking twice is still a 204."""
    await LikeService().unlike_article(user.id, article_id)


@router.get("/users/me/likes", response_model=list[Article])
async def get_liked_articles(
    limit: int = Query(default=20, ge=1, le=50),
    user: User = Depends(get_current_user),
) -> list[Article]:
    """Articles this user has liked, most recently liked first."""
    return await LikeService().get_user_likes(user.id, limit=limit)
