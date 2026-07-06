"""
New World Encyclopedia content source.

New World Encyclopedia has no public search API, but its articles are
editorially-reviewed content originally derived from Wikipedia, so its
URL pattern (/entry/{Topic}) mirrors Wikipedia's (/wiki/{Topic}) closely
enough to guess directly. robots.txt explicitly allows /entry/ (checked
2026-07-05) while disallowing /entry/Special:* (search/admin pages), so
this direct-URL approach is fully compliant -- it just skips the search
step entirely and lets the base class's existing extract()/_scrape_url()
failure-handling drop the guess if it 404s.
"""

import logging
from typing import Dict, List

from .base import ContentSource

logger = logging.getLogger(__name__)

BASE_URL = "https://www.newworldencyclopedia.org/entry/"


class NewWorldEncyclopediaSource(ContentSource):
    """New World Encyclopedia content source, via a direct URL guess (no search API)."""

    name = "new_world_encyclopedia"

    def search_topic(
        self,
        topic: str,
        max_results: int = 5
    ) -> List[Dict[str, str]]:
        """
        Return a single candidate URL guessed from the topic name.

        No search API exists for this site, so this optimistically builds
        the likely article URL; if it doesn't resolve, the base class's
        extract()/_scrape_url() will raise and it gets filtered out like
        any other failed page.
        """
        slug = topic.strip().replace(" ", "_")
        url = f"{BASE_URL}{slug}"
        logger.info(f"Guessing New World Encyclopedia URL for '{topic}': {url}")
        return [{
            "title": topic,
            "url": url,
            "summary": topic,
        }]
