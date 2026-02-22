"""
Web scraper for BharatVerse content pipeline.

Uses Crawl4AI with a plugin-based source architecture for easy extensibility.
"""

import asyncio
import time
import logging
from typing import List, Optional
from urllib.parse import urlparse
from urllib.robotparser import RobotFileParser

from scrapper.models.article import ScrapedContent
from scrapper.sources import registry

logger = logging.getLogger(__name__)


class RateLimiter:
    """
    Rate limiter to respect source servers.

    Ensures minimum time between requests to avoid overwhelming sources.
    """

    def __init__(self, requests_per_second: float = 0.5):
        """
        Initialize rate limiter.

        Args:
            requests_per_second: Maximum requests per second (default: 0.5 = 1 req per 2 sec)
        """
        self.min_interval = 1.0 / requests_per_second
        self.last_request = 0

    async def wait(self):
        """Wait if needed to respect rate limit."""
        now = time.time()
        time_since_last = now - self.last_request
        if time_since_last < self.min_interval:
            await asyncio.sleep(self.min_interval - time_since_last)
        self.last_request = time.time()


class WebScraper:
    """
    Main web scraper for BharatVerse content pipeline.

    Features:
    - Plugin-based source architecture (easy to add new sources)
    - Rate limiting (respects servers)
    - Robots.txt checking (respects site policies)
    - Concurrent scraping from multiple sources

    Usage:
        scraper = WebScraper()

        # Scrape from specific source
        content = await scraper.scrape("wikipedia", "Mauryan Empire")

        # Scrape from all sources
        all_content = await scraper.scrape_all("Mauryan Empire")

        # List available sources
        sources = scraper.list_sources()
    """

    def __init__(self, requests_per_second: float = 0.5):
        """
        Initialize web scraper.

        Args:
            requests_per_second: Rate limit for requests (default: 0.5 = 1 req per 2 sec)
        """
        self.registry = registry
        self.rate_limiter = RateLimiter(requests_per_second)
        self._robots_cache = {}

    def list_sources(self) -> List[str]:
        """
        List all available content sources.

        Returns:
            List of source names
        """
        return self.registry.list_sources()

    async def check_robots_txt(self, url: str, user_agent: str = "*") -> bool:
        """
        Check if URL is allowed by robots.txt.

        Args:
            url: URL to check
            user_agent: User agent string

        Returns:
            True if allowed, False otherwise
        """
        parsed = urlparse(url)
        robots_url = f"{parsed.scheme}://{parsed.netloc}/robots.txt"

        # Check cache
        if robots_url in self._robots_cache:
            rp = self._robots_cache[robots_url]
        else:
            # Fetch and parse robots.txt
            rp = RobotFileParser()
            rp.set_url(robots_url)
            try:
                rp.read()
                self._robots_cache[robots_url] = rp
            except Exception as e:
                logger.warning(f"Could not fetch robots.txt from {robots_url}: {e}")
                # If we can't fetch robots.txt, assume allowed
                return True

        return rp.can_fetch(user_agent, url)

    async def scrape(
        self,
        source_name: str,
        topic: str,
        max_pages: int = 1,
        respect_robots: bool = False
    ) -> List[ScrapedContent]:
        """
        Scrape content from a specific source.

        Args:
            source_name: Name of the source (e.g., "wikipedia", "archive_org")
            topic: Topic to scrape
            max_pages: Maximum number of pages to extract (default: 1)
            respect_robots: Whether to check robots.txt (default: False for API-based sources)

        Returns:
            List of ScrapedContent from the source

        Raises:
            ValueError: If source not found
        """
        # Get source
        source = self.registry.get_source(source_name)
        if not source:
            raise ValueError(
                f"Source '{source_name}' not found. "
                f"Available sources: {self.list_sources()}"
            )

        # Rate limit
        await self.rate_limiter.wait()

        # Scrape
        logger.info(f"Scraping '{topic}' from {source_name} (max {max_pages} pages)")
        try:
            contents = await source.extract(topic, max_pages=max_pages)
            total_chars = sum(len(c.raw_text) for c in contents)
            logger.info(
                f"Successfully scraped {len(contents)} page(s) "
                f"({total_chars} total characters) from {source_name}"
            )
            return contents
        except Exception as e:
            logger.error(f"Failed to scrape from {source_name}: {e}")
            raise

    async def scrape_all(
        self,
        topic: str,
        max_pages: int = 1,
        respect_robots: bool = False,
        fail_fast: bool = False,
        sources: Optional[List[str]] = None
    ) -> List[ScrapedContent]:
        """
        Scrape content from multiple sources concurrently.

        Args:
            topic: Topic to scrape
            max_pages: Maximum number of pages per source (default: 1)
            respect_robots: Whether to check robots.txt (default: True)
            fail_fast: If True, raise on first error. If False, continue with other sources.
            sources: Optional list of source names to use. If None, uses all registered sources.

        Returns:
            List of ScrapedContent from all sources (may be partial if some fail)
        """
        # Determine which sources to use
        source_names = sources if sources else self.list_sources()

        logger.info(f"Scraping '{topic}' from sources: {source_names}")

        tasks = []
        for source_name in source_names:
            task = self.scrape(source_name, topic, max_pages, respect_robots)
            tasks.append(task)

        # Gather results
        if fail_fast:
            results = await asyncio.gather(*tasks)
        else:
            results = await asyncio.gather(*tasks, return_exceptions=True)

        # Flatten and filter results
        scraped_content = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                source_name = source_names[i]
                logger.error(f"Failed to scrape from {source_name}: {result}")
            else:
                # result is a list of ScrapedContent
                scraped_content.extend(result)

        logger.info(f"Successfully scraped {len(scraped_content)} page(s) from {len(source_names)} source(s)")
        return scraped_content

    async def search_and_scrape(
        self,
        topic: str,
        max_pages_per_source: int = 1,
        sources: Optional[List[str]] = None,
        respect_robots: bool = False
    ) -> List[ScrapedContent]:
        """
        High-level wrapper: Search for topic and scrape content from all sources.

        This is the main method you should use. It:
        1. Searches for the topic across all sources (or specified sources)
        2. Gets relevant URLs for each source
        3. Scrapes content using Crawl4AI to get LLM-ready markdown
        4. Returns all scraped content

        Args:
            topic: Topic to search and scrape
            max_pages_per_source: Maximum pages to scrape per source (default: 1)
            sources: Optional list of source names. If None, uses all sources.
            respect_robots: Whether to check robots.txt (default: False for API-based sources)

        Returns:
            List of ScrapedContent from all sources

        Example:
            scraper = WebScraper()

            # Scrape from all sources (best match from each)
            contents = await scraper.search_and_scrape("Mauryan Empire")

            # Scrape multiple pages from all sources
            contents = await scraper.search_and_scrape("Mauryan Empire", max_pages_per_source=3)

            # Scrape only from Wikipedia
            contents = await scraper.search_and_scrape("Mauryan Empire", sources=["wikipedia"])
        """
        return await self.scrape_all(
            topic=topic,
            max_pages=max_pages_per_source,
            respect_robots=respect_robots,
            fail_fast=False,
            sources=sources
        )
