"""
Base classes for content source plugins.

To add a new source:
1. Create a new file in scrapper/sources/ (e.g., britannica.py)
2. Subclass ContentSource
3. Implement search_topic() and optionally customize extract()
4. Register it in __init__.py

Example:
    class BritannicaSource(ContentSource):
        name = "britannica"

        def search_topic(self, topic: str, max_results: int = 5) -> List[Dict[str, str]]:
            # Search and return results with title, url, summary, etc.
            return [{'title': '...', 'url': '...', 'summary': '...'}]
"""

from abc import ABC, abstractmethod
from typing import Awaitable, Callable, Optional, Dict, List
from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CacheMode
from datetime import datetime, timezone
import logging
import asyncio

from scrapper.models.article import ScrapedContent
from scrapper.user_agent import USER_AGENT

logger = logging.getLogger(__name__)

# Whether robots.txt lets the pipeline fetch a URL; WebScraper.check_robots_txt is the real one.
UrlCheck = Callable[[str], Awaitable[bool]]


class RobotsDisallowed(Exception):
    """robots.txt does not let the pipeline fetch this page."""


async def ensure_allowed(url: str, allowed: Optional[UrlCheck]) -> None:
    """Raise RobotsDisallowed unless `allowed` (None skips the check) lets the pipeline fetch `url`."""
    if allowed is not None and not await allowed(url):
        raise RobotsDisallowed(f"robots.txt disallows {url}")


class ContentSource(ABC):
    """
    Abstract base class for content sources.

    Each source must implement:
    - name: Unique identifier for the source
    - search_topic(): Search for topic and return results with metadata

    Optionally override:
    - extract(): Custom extraction logic
    - get_browser_config(): Custom browser settings
    - get_crawler_config(): Custom crawler settings
    """

    name: str = "base"

    def __init__(self):
        self.browser_config = self.get_browser_config()
        self.crawler_config = self.get_crawler_config()

    @abstractmethod
    def search_topic(
        self,
        topic: str,
        max_results: int = 5
    ) -> List[Dict[str, str]]:
        """
        Search for a topic and return results with metadata.

        Args:
            topic: The topic to search for (e.g., "Mauryan Empire")
            max_results: Maximum number of results to return

        Returns:
            List of dicts with at minimum: 'title', 'url', 'summary'
            Can include additional fields like 'page_id', 'date', etc.

        Example:
            [
                {
                    'title': 'Maurya Empire',
                    'url': 'https://...',
                    'summary': 'The Maurya Empire was...',
                    'page_id': 123  # optional
                },
                ...
            ]
        """
        pass

    def get_browser_config(self) -> BrowserConfig:
        """
        Get browser configuration for this source.
        Override to customize browser behavior.
        """
        return BrowserConfig(
            headless=True,
            java_script_enabled=True,
            verbose=False,
            user_agent=USER_AGENT,
        )

    def get_crawler_config(self) -> CrawlerRunConfig:
        """
        Get crawler configuration for this source.
        Override to customize crawling behavior.
        """
        return CrawlerRunConfig(
            cache_mode=CacheMode.BYPASS,
            page_timeout=30000,  # 30 seconds
            word_count_threshold=100,  # Minimum words
        )

    async def extract(
        self,
        topic: str,
        max_pages: int = 1,
        allowed: Optional[UrlCheck] = None
    ) -> List[ScrapedContent]:
        """
        Extract content from this source for the given topic.

        Default implementation:
        1. Calls search_topic() to get results
        2. Scrapes each result URL that robots.txt allows with Crawl4AI

        Override this method if you need custom extraction logic; check every page it fetches with
        ensure_allowed().

        Args:
            topic: The topic to scrape
            max_pages: Maximum number of pages to extract (default: 1)
            allowed: Whether robots.txt allows a URL; None fetches without checking

        Returns:
            List of ScrapedContent with extracted data

        Raises:
            Exception: If scraping fails
        """

        # Search for topic
        results = self.search_topic(topic, max_results=max_pages)

        if not results:
            raise ValueError(f"No results found for topic: {topic}")

        logger.info(f"Extracting content from {len(results)} page(s) for {self.name}")

        # Extract content from each result
        tasks = [self._scrape_url(result, allowed) for result in results]
        contents = await asyncio.gather(*tasks, return_exceptions=True)

        # Filter out exceptions
        valid_contents = []
        for i, content in enumerate(contents):
            if isinstance(content, Exception):
                logger.error(f"Failed to extract {results[i]['title']}: {content}")
            else:
                valid_contents.append(content)

        logger.info(f"Successfully extracted {len(valid_contents)} page(s)")
        return valid_contents

    async def _scrape_url(
        self,
        result: Dict[str, str],
        allowed: Optional[UrlCheck] = None
    ) -> ScrapedContent:
        """
        Helper method to scrape a single URL.

        Args:
            result: Dict with at minimum 'url', 'title', 'summary'
            allowed: Whether robots.txt allows a URL; None fetches without checking

        Returns:
            ScrapedContent

        Raises:
            RobotsDisallowed: If robots.txt does not allow the URL
        """
        url = result['url']
        await ensure_allowed(url, allowed)

        logger.info(f"Scraping {self.name}: {url}")

        async with AsyncWebCrawler(config=self.browser_config) as crawler:
            crawl_result = await crawler.arun(url=url, config=self.crawler_config)

            if not crawl_result.success:
                raise Exception(f"Failed to scrape {url}: {crawl_result.error_message}")

            # A str of the raw markdown that also carries Crawl4AI's other variants (None if none was made).
            if not isinstance(crawl_result.markdown, str):
                raise Exception(f"Unexpected markdown format: {type(crawl_result.markdown)}")
            markdown_text = str(crawl_result.markdown)

            # Extract images
            images = []
            if hasattr(crawl_result, 'media') and crawl_result.media:
                for img in crawl_result.media.get('images', [])[:10]:  # Limit to 10 images
                    images.append({
                        'url': img.get('src', ''),
                        'alt_text': img.get('alt', ''),
                        'caption': img.get('title'),
                    })

            # Build metadata from search result + crawl result
            metadata = {
                'source': self.name,
                'word_count': len(markdown_text.split()),
                **result,  # Include all fields from search result
                **crawl_result.metadata  # Include crawl metadata
            }

            content = ScrapedContent(
                source_url=url,
                title=result.get('title', crawl_result.metadata.get('title', 'Untitled')),
                raw_text=markdown_text,
                images=images,
                metadata=metadata,
                scraped_at=datetime.now(timezone.utc)
            )

            return content


class SourceRegistry:
    """Registry for managing content sources."""

    def __init__(self):
        self._sources: Dict[str, ContentSource] = {}

    def register(self, source: ContentSource):
        """Register a new content source."""
        self._sources[source.name] = source
        logger.info(f"Registered source: {source.name}")

    def get_source(self, name: str) -> Optional[ContentSource]:
        """Get a source by name."""
        return self._sources.get(name)

    def list_sources(self) -> List[str]:
        """List all registered source names."""
        return list(self._sources.keys())
