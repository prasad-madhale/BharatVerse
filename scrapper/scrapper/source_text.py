"""Shared source-text budgeting for the generation and critic prompts, so both see the
exact same (truncated) view of the scraped material."""

from scrapper.models.article import ScrapedContent

# Cap on how much scraped source text goes into a single LLM call.
MAX_SOURCE_CHARS = 15000


def build_source_text(scraped_content: list[ScrapedContent], max_chars: int = MAX_SOURCE_CHARS) -> str:
    # Give each source a fair, even share of the character budget rather than truncating the
    # concatenated whole -- otherwise one oversized source (e.g. a long but tangential Wikipedia
    # page) can silently crowd out every other source's content entirely, even when those
    # sources are more on-topic.
    per_source_budget = max(1, max_chars // len(scraped_content))
    return "\n\n".join(
        f"--- Source: {c.source_url} ---\n{c.raw_text[:per_source_budget]}"
        for c in scraped_content
    )
