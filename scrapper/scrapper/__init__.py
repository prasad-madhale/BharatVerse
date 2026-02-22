"""
BharatVerse Web Scraper

A plugin-based web scraper for historical content.
"""

from .web_scraper import WebScraper, RateLimiter
from .models import Article, ScrapedContent, Citation, Section
from .sources import ContentSource, SourceRegistry, WikipediaSource, ArchiveOrgSource, registry

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
    'registry',
]
