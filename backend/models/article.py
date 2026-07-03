"""
Article models specific to the backend's storage layer.

The full, assembled article (title, content, sections, citations, etc.) is
common.models.Article -- used directly as the API response shape. This
module only adds ArticleRecord, the *metadata-only* row shape stored in the
`articles` Postgres table (see backend/database/schema.sql): full article
content lives in Supabase Storage as a JSON file, referenced by
content_file_path, not inline in the row.
"""

from datetime import date, datetime
from typing import Optional
from pydantic import BaseModel, Field


class ArticleRecord(BaseModel):
    """Shape of a row in the `articles` Postgres table."""

    id: str
    title: str
    summary: str
    date: date
    reading_time_minutes: int
    author: str = "BharatVerse AI"
    tags: list[str] = Field(default_factory=list)
    image_url: Optional[str] = None
    content_file_path: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
