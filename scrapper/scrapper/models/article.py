from datetime import datetime
from typing import List
from pydantic import BaseModel, Field


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
