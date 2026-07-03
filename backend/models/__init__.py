"""
Data models and schemas.

Note: the client-facing Article model lives in common/models.py (shared
with scrapper/). This package only holds backend-storage-specific shapes.
"""

from backend.models.article import ArticleRecord

__all__ = [
    "ArticleRecord",
]
