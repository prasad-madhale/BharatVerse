"""
Wikipedia content source.

Uses Wikipedia API for search/discovery + Crawl4AI for content extraction.
"""

import wikipedia
import logging
from typing import List, Dict, Optional
from crawl4ai import CrawlerRunConfig, CacheMode
from .base import ContentSource

logger = logging.getLogger(__name__)


class WikipediaSource(ContentSource):
    """Wikipedia content source with hybrid API + scraping approach."""

    name = "wikipedia"

    def __init__(self):
        super().__init__()
        wikipedia.set_user_agent('BharatVerse/1.0 (https://github.com/bharatverse)')
        wikipedia.set_lang('en')

    def get_crawler_config(self) -> CrawlerRunConfig:
        """
        Scope extraction to Wikipedia's actual article content, excluding the
        navigation chrome (sidebar, search box, language links, tool boxes)
        that would otherwise dominate the first several thousand characters
        of the extracted markdown -- #mw-content-text is MediaWiki's stable
        content-area id, present on every Wikipedia article page.
        """
        return CrawlerRunConfig(
            cache_mode=CacheMode.BYPASS,
            page_timeout=30000,
            word_count_threshold=100,
            css_selector="#mw-content-text",
        )

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
            search_results = self._search_titles(topic, max_results, auto_suggest)

            if not search_results:
                logger.warning(f"No Wikipedia results found for: {topic}")
                return []

            logger.info(f"Found {len(search_results)} results")

            results = []
            seen_urls = set()
            for title in search_results:
                page_info = self._get_page_info(title)
                if not page_info:
                    continue
                # Two search hits can resolve to the same article (redirects,
                # near-duplicate titles). Scraping it twice wastes a slot of the
                # per-source character budget for no new content.
                if page_info['url'] in seen_urls:
                    logger.debug(f"Skipping duplicate Wikipedia URL: {page_info['url']}")
                    continue
                seen_urls.add(page_info['url'])
                results.append(page_info)

            logger.info(f"Successfully retrieved {len(results)} pages")
            logger.debug(f"Wikipedia results: {results}")
            return results

        except Exception as e:
            logger.error(f"Search failed for '{topic}': {e}")
            return []

    def _search_titles(self, topic: str, max_results: int, auto_suggest: bool) -> List[str]:
        """
        Titles of the pages matching `topic`, best match first.

        wikipedia.search() returns a plain list of titles normally, but a
        (titles, suggestion) tuple when called with suggestion=True. The tuple
        must be unpacked: iterating it as if it were the title list yields the
        whole list as its first "title" and the suggestion string as its
        second, which resolves to the wrong pages.
        """
        if not auto_suggest:
            return wikipedia.search(topic, results=max_results)

        titles, suggestion = wikipedia.search(topic, results=max_results, suggestion=True)
        if not titles and suggestion:
            logger.info(f"No results for '{topic}'; retrying with Wikipedia's suggestion '{suggestion}'")
            titles = wikipedia.search(suggestion, results=max_results)
        return titles

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
