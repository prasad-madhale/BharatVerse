"""
Content source plugins for web scraping.

This module provides a plugin-based architecture for adding new content sources.
Each source is a separate class that implements the ContentSource interface.
"""

from .base import ContentSource, SourceRegistry
from .wikipedia import WikipediaSource
from .archive_org import ArchiveOrgSource
from .new_world_encyclopedia import NewWorldEncyclopediaSource

# Register all available sources
registry = SourceRegistry()
registry.register(WikipediaSource())
registry.register(ArchiveOrgSource())
registry.register(NewWorldEncyclopediaSource())

__all__ = [
    'ContentSource',
    'SourceRegistry',
    'WikipediaSource',
    'ArchiveOrgSource',
    'NewWorldEncyclopediaSource',
    'registry',
]
