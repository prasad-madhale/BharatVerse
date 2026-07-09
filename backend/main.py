"""
FastAPI application entry point.

Run with: uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.api.articles import router as articles_router
from backend.api.auth import router as auth_router
from backend.config import get_settings

settings = get_settings()

app = FastAPI(title=settings.app_name, version=settings.app_version)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(articles_router, prefix=settings.api_prefix)
app.include_router(auth_router, prefix=settings.api_prefix)


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}
