"""
FastAPI application entry point.

Run with: uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.api.articles import router as articles_router
from backend.api.auth import router as auth_router
from backend.api.likes import router as likes_router
from backend.api.middleware import add_request_middleware
from backend.api.search import router as search_router
from backend.config import Settings, get_settings
from backend.utils.logging_config import configure_logging


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)
    app = FastAPI(title=settings.app_name, version=settings.app_version)

    add_request_middleware(app, settings.rate_limit_requests_per_minute)
    # Added last so it is outermost: even a refused request gets the headers a browser needs to read the refusal.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Before articles_router, whose /articles/{article_id} would capture /articles/search.
    app.include_router(search_router, prefix=settings.api_prefix)
    app.include_router(articles_router, prefix=settings.api_prefix)
    app.include_router(auth_router, prefix=settings.api_prefix)
    app.include_router(likes_router, prefix=settings.api_prefix)

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok"}

    return app


app = create_app()
