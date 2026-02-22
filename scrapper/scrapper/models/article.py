from datetime import datetime, date
from typing import Optional, List
from pydantic import BaseModel, Field


class Citation(BaseModel):
    """
    Represents a citation/reference in an article.
    """
    text: str = Field(
        ...,
        description="The citation text or description",
    )
    source_url: str = Field(
        ...,
        description="The URL of the source",
    )
    source_name: str = Field(
        ...,
        description="The name of the source (e.g., 'Wikipedia', 'Archive.org')",
    )
    accessed_date: datetime = Field(
        ...,
        description="When the source was accessed",
    )


class Section(BaseModel):
    """
    Represents a section within an article.
    """
    heading: str = Field(
        ...,
        description="The section heading",
    )
    content: str = Field(
        ...,
        description="The section content in Markdown format",
    )
    order: int = Field(
        ...,
        description="The order of this section in the article",
    )


class Article(BaseModel):
    """
    Represents a complete historical article with all metadata.
    Matches the design document schema for BharatVerse MVP.
    """
    id: str = Field(
        ...,
        description="Unique article identifier (format: art_YYYYMMDD_NNN)",
    )
    title: str = Field(
        ...,
        description="The title of the article",
    )
    summary: str = Field(
        ...,
        description="A 2-3 sentence summary of the article",
    )
    content: str = Field(
        ...,
        description="The full article content in Markdown format",
    )
    sections: List[Section] = Field(
        default_factory=list,
        description="Structured sections of the article",
    )
    citations: List[Citation] = Field(
        default_factory=list,
        description="Citations and references used in the article",
    )
    publication_date: date = Field(
        ...,
        description="Publication date of the article",
    )
    reading_time_minutes: int = Field(
        ...,
        description="Estimated reading time in minutes (10-15 for MVP)",
    )
    author: str = Field(
        default="BharatVerse AI",
        description="The author of the article",
    )
    tags: List[str] = Field(
        default_factory=list,
        description="Tags/keywords for categorization (e.g., ['ancient-india', 'mauryan-empire'])",
    )
    image_url: Optional[str] = Field(
        default=None,
        description="URL of the featured image for the article",
    )
    created_at: datetime = Field(
        default_factory=datetime.now,
        description="When the article was created",
    )
    updated_at: datetime = Field(
        default_factory=datetime.now,
        description="When the article was last updated",
    )


class ScrapedContent(BaseModel):
    """
    Represents raw content scraped from a source.
    """
    source_url: str = Field(
        ...,
        description="The URL of the scraped source",
    )
    title: str = Field(
        ...,
        description="The title from the source",
    )
    raw_text: str = Field(
        ...,
        description="The raw markdown content extracted (LLM-ready)",
    )
    images: List[dict] = Field(
        default_factory=list,
        description="List of images with URLs and metadata",
    )
    metadata: dict = Field(
        default_factory=dict,
        description="Additional metadata from the source",
    )
    scraped_at: datetime = Field(
        default_factory=datetime.now,
        description="When the content was scraped",
    )
