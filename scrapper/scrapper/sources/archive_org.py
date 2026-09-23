"""
Archive.org content source.

Uses Internet Archive API for search + Crawl4AI for content extraction.
"""

import logging
from typing import List, Dict
from .base import ContentSource
from internetarchive import search_items

logger = logging.getLogger(__name__)


class ArchiveOrgSource(ContentSource):
    """Archive.org content source with API search."""

    name = "archive_org"

    def search_topic(
        self,
        topic: str,
        max_results: int = 5
    ) -> List[Dict[str, str]]:
        """
        Search Archive.org for items related to the topic.

        Args:
            topic: Topic to search for
            max_results: Maximum number of results to return

        Returns:
            List of dicts with 'title', 'url', 'summary', 'identifier'
        """
        try:
            logger.info(f"Searching Archive.org for: '{topic}' (max {max_results} results)")

            # Restricted to mediatype:texts: an unrestricted search returns whatever Archive.org's
            # huge, heterogeneous catalog scores as a loose match -- often a video, an image, or an
            # unrelated item that just shares a word, with little or no extractable text (measured:
            # for "Rani ki Vav", an unrestricted search's top hits included a YouTube video and an
            # unrelated audio-art collection page; restricted to texts, all five hits were real
            # reference material -- books, papers and heritage-site documents about the actual topic).
            search = search_items(
                f"{topic} AND mediatype:texts",
                fields=['identifier', 'title', 'description', 'date', 'mediatype'],
                params={'rows': max_results}
            )

            results = []
            for item in search:
                identifier = item.get('identifier', '')
                if not identifier:
                    continue

                # Build URL
                url = f"https://archive.org/details/{identifier}"

                # Get description/summary
                description = item.get('description', '')
                if isinstance(description, list):
                    description = ' '.join(description)

                results.append({
                    'title': item.get('title', identifier),
                    'url': url,
                    'summary': description or f'Archive.org item: {identifier}',
                    'identifier': identifier,
                    'date': item.get('date', ''),
                    'mediatype': item.get('mediatype', ''),
                })

                if len(results) >= max_results:
                    break

            logger.info(f"Found {len(results)} results from Archive.org")
            logger.debug(f"Archive.org results: {results}")
            return results

        except ImportError:
            logger.error("internetarchive library not installed. Run: pip install internetarchive")
            return []
        except Exception as e:
            logger.error(f"Archive.org search failed for '{topic}': {e}")
            return []
