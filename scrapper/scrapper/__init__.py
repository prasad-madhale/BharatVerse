"""
BharatVerse Web Scraper

A plugin-based web scraper for historical content.
"""

from .web_scraper import WebScraper, RateLimiter
from .models import ScrapedContent
from .sources import (
    ContentSource, SourceRegistry, WikipediaSource, ArchiveOrgSource,
    NewWorldEncyclopediaSource, registry,
)
from .article_generator import ArticleGenerator, ArticleGenerationError
from .topic_generator import TopicGenerator, TopicGenerationError
from .content_validator import ContentValidator
from common.models import Article, Citation, Section

__version__ = "0.1.0"

__all__ = [
    'WebScraper',
    'RateLimiter',
    'Article',
    'ScrapedContent',
    'Citation',
    'Section',
    'ContentSource',
    'SourceRegistry',
    'WikipediaSource',
    'ArchiveOrgSource',
    'NewWorldEncyclopediaSource',
    'registry',
    'ArticleGenerator',
    'ArticleGenerationError',
    'TopicGenerator',
    'TopicGenerationError',
    'ContentValidator',
]
