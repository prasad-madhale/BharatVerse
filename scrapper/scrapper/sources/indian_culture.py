"""
Indian Culture Portal (Ministry of Culture) content source.

The site is a React SPA behind bot-detection that blocks plain HTTP requests -- even to its own
JSON search API -- with a 403; a real browser session gets through. Search needs to go through the
page's own search box, not a URL query parameter: navigating straight to a `?search_api_fulltext=`
URL does not filter anything (confirmed: it returned all ~550,000 catalog items unfiltered), while
typing into the box and submitting calls `/api/global-search-api-new` with the query correctly
applied. That interaction is measurably flaky -- confirmed intermittent failures getting the search
box interactable -- so it is retried with backoff.

Most catalog items are archival-record metadata (a photo, a museum accession, a file scan) with no
body text at all; only a minority -- measured, e.g. items of type "Legendary Figures of India" --
carry real prose. A search often returns thousands of the former and few or none of the latter, so
results are kept only if they carry enough body text to be real content, same idea as archive_org.py
restricting to mediatype:texts. The API conveniently returns that body as HTML inline with the
search results, so extract() converts it directly instead of visiting a second page to render it.
"""

import asyncio
import logging
import time
from datetime import datetime, timezone
from typing import Dict, List
from urllib.parse import quote

from crawl4ai import DefaultMarkdownGenerator
from playwright.async_api import async_playwright
from playwright.sync_api import sync_playwright

from .base import ContentSource
from scrapper.models.article import ScrapedContent

logger = logging.getLogger(__name__)

PORTAL_URL = "https://www.indianculture.gov.in"
MIN_BODY_CHARS = 500  # below this, a result is an archival record with no real content
SEARCH_ATTEMPTS = 3
SEARCH_BACKOFF_SECONDS = 3


def _is_search_response(url: str) -> bool:
    return "global-search-api-new" in url and "search_api_fulltext=" in url


def _results_url(topic: str) -> str:
    return f"{PORTAL_URL}/indian-culture-repository/searchtext={quote(topic)}"


def _good_results(payload: dict, max_results: int) -> List[dict]:
    results = (payload or {}).get("results", [])
    good = [r for r in results if len(r.get("body") or "") > MIN_BODY_CHARS]
    return good[:max_results]


class IndianCultureSource(ContentSource):
    """Indian Culture Portal content source. Needs a real browser; see module docstring."""

    name = "indian_culture"

    def search_topic(self, topic: str, max_results: int = 5) -> List[Dict[str, str]]:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            try:
                payload = self._search_sync(browser, topic)
            finally:
                browser.close()

        url = _results_url(topic)
        return [
            {"title": r.get("title") or topic, "url": url, "summary": r.get("title") or topic}
            for r in _good_results(payload, max_results)
        ]

    async def extract(self, topic: str, max_pages: int = 1) -> List[ScrapedContent]:
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            try:
                payload = await self._search_async(browser, topic)
            finally:
                await browser.close()

        good = _good_results(payload, max_pages)
        if not good:
            raise ValueError(f"No Indian Culture Portal results with real content for: {topic}")

        url = _results_url(topic)
        generator = DefaultMarkdownGenerator()
        return [
            ScrapedContent(
                source_url=url,
                title=r.get("title") or topic,
                raw_text=generator.generate_markdown(r.get("body") or "", base_url=url).raw_markdown,
                images=[],
                metadata={"source": self.name, "content_type": r.get("type") or ""},
                scraped_at=datetime.now(timezone.utc),
            )
            for r in good
        ]

    async def _search_async(self, browser, topic: str) -> dict:
        last_error: Exception | None = None
        for attempt in range(1, SEARCH_ATTEMPTS + 1):
            page = None
            try:
                page = await browser.new_page()
                await page.goto(PORTAL_URL, wait_until="load", timeout=30000)
                box = page.locator('input[type="search"]').first
                await box.wait_for(state="visible", timeout=15000)
                async with page.expect_response(
                    lambda r: _is_search_response(r.url), timeout=15000
                ) as response_info:
                    await box.click()
                    await box.fill(topic)
                    await box.press("Enter")
                return await (await response_info.value).json()
            except Exception as e:
                last_error = e
                logger.warning(f"Indian Culture Portal search attempt {attempt} of {SEARCH_ATTEMPTS} "
                               f"failed for '{topic}': {e}")
                if attempt < SEARCH_ATTEMPTS:
                    await asyncio.sleep(SEARCH_BACKOFF_SECONDS)
            finally:
                if page is not None:
                    await page.close()
        raise last_error

    def _search_sync(self, browser, topic: str) -> dict:
        last_error: Exception | None = None
        for attempt in range(1, SEARCH_ATTEMPTS + 1):
            page = None
            try:
                page = browser.new_page()
                page.goto(PORTAL_URL, wait_until="load", timeout=30000)
                box = page.locator('input[type="search"]').first
                box.wait_for(state="visible", timeout=15000)
                with page.expect_response(lambda r: _is_search_response(r.url), timeout=15000) as response_info:
                    box.click()
                    box.fill(topic)
                    box.press("Enter")
                return response_info.value.json()
            except Exception as e:
                last_error = e
                logger.warning(f"Indian Culture Portal search attempt {attempt} of {SEARCH_ATTEMPTS} "
                               f"failed for '{topic}': {e}")
                if attempt < SEARCH_ATTEMPTS:
                    time.sleep(SEARCH_BACKOFF_SECONDS)
            finally:
                if page is not None:
                    page.close()
        raise last_error
