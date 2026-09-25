"""
Recovers the real Wikipedia title an article was generated from.

An article's .title is an LLM-written headline (e.g. "Haldighati, 1576: The Battle Nobody Can
Agree On"), not the real Wikipedia page title it was generated from ("Battle of Haldighati") --
image_sourcing.py's Wikipedia lookup, and a re-scrape for reprocess_articles.py, both need the
real one. Recovered from the article's own Wikipedia citation, since the original search topic
and scraped source text are never persisted. Shared by backfill_images.py and
reprocess_articles.py rather than duplicated.
"""

from urllib.parse import unquote

from common.models import Article


def recover_topic(article: Article) -> str:
    """The real Wikipedia title, recovered from the article's own Wikipedia citation, falling
    back to the article's (LLM-written headline) title when there is no Wikipedia citation to
    recover it from."""
    for citation in article.citations:
        if citation.source_name == "wikipedia":
            title = citation.source_url.rstrip("/").rsplit("/", 1)[-1]
            return unquote(title).replace("_", " ")
    return article.title
