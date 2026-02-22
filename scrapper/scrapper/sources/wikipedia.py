"""
Wikipedia content source.

Uses Wikipedia API for search/discovery + Crawl4AI for content extraction.
"""

import wikipedia
import logging
from typing import List, Dict, Optional
from .base import ContentSource

logger = logging.getLogger(__name__)


class WikipediaSource(ContentSource):
    """Wikipedia content source with hybrid API + scraping approach."""

    name = "wikipedia"

    def __init__(self):
        super().__init__()
        wikipedia.set_user_agent('BharatVerse/1.0 (https://github.com/bharatverse)')
        wikipedia.set_lang('en')

    def search_topic(
        self,
        topic: str,
        max_results: int = 5,
        auto_suggest: bool = True
    ) -> List[Dict[str, str]]:
        """
        Search for a topic and return multiple relevant pages.

        Args:
            topic: Topic to search for (can be fuzzy, any case)
            max_results: Maximum number of results to return
            auto_suggest: Use Wikipedia's auto-suggest

        Returns:
            List of dicts with 'title', 'url', 'summary', 'page_id'
        """
        logger.info(f"Searching Wikipedia for: '{topic}' (max {max_results} results)")

        try:
            search_results = wikipedia.search(topic, results=max_results, suggestion=auto_suggest)

            if not search_results:
                logger.warning(f"No Wikipedia results found for: {topic}")
                return []

            logger.info(f"Found {len(search_results)} results")

            results = []
            for title in search_results:
                page_info = self._get_page_info(title)
                if page_info:
                    results.append(page_info)

            logger.info(f"Successfully retrieved {len(results)} pages")
            logger.debug(f"Wikipedia results: {results}")
            return results

        except Exception as e:
            logger.error(f"Search failed for '{topic}': {e}")
            return []

    def _get_page_info(self, title: str) -> Optional[Dict[str, str]]:
        """Get page information from Wikipedia API."""
        try:
            page = wikipedia.page(title, auto_suggest=False)
            return {
                'title': page.title,
                'url': page.url,
                'summary': page.summary,
                'page_id': page.pageid,
            }
        except wikipedia.exceptions.DisambiguationError as e:
            logger.info(f"'{title}' is disambiguation, trying first option")
            if e.options:
                try:
                    page = wikipedia.page(e.options[0], auto_suggest=False)
                    return {
                        'title': page.title,
                        'url': page.url,
                        'summary': page.summary,
                        'page_id': page.pageid,
                    }
                except Exception:
                    pass
            return None
        except wikipedia.exceptions.PageError:
            logger.warning(f"Page not found: {title}")
            return None
        except Exception as e:
            logger.error(f"Error fetching page '{title}': {e}")
            return None
