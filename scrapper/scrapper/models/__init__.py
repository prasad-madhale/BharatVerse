"""
Data models for BharatVerse scraper.

Note: Article, Section, and Citation live in common/models.py, shared with
backend/ -- only ScrapedContent (scraper-pipeline-specific) is defined here.
"""

from .article import ScrapedContent

__all__ = [
    'ScrapedContent',
]
