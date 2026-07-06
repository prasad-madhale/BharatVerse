"""
LLM-powered article generation for the BharatVerse content pipeline.

Turns raw ScrapedContent into a structured, citable Article by prompting
an LLM (via common.llm_provider) for the creative parts (title, summary,
sections, tags) while this module derives everything else -- citations,
reading time, content assembly -- directly from the scraped source data
rather than trusting the LLM to produce it accurately.
"""

import logging
from datetime import date, datetime, timezone

import json_repair

from common.llm_provider import LLMProvider, get_llm_provider
from common.models import Article, Citation, Section
from scrapper.models.article import ScrapedContent

logger = logging.getLogger(__name__)

# Rough words-per-minute reading speed used to derive reading_time_minutes.
# Chosen so the BRD's stated 1500-2500 word target maps to ~10-15 minutes.
WORDS_PER_MINUTE = 150

# Cap on how much scraped source text is sent to the LLM per generation call.
MAX_SOURCE_CHARS = 15000

PROMPT_TEMPLATE = """# Role
You are a historical content curator for BharatVerse, specializing in Indian history. You write for
a Gen Z / young-adult audience who are curious but time-poor: they'll drop off if an article reads
like a textbook, but they'll stay for surprising, vivid, well-told history -- as long as every claim
is true.

# Task
Transform the scraped source material below (topic: "{topic}") into a structured historical article.

# Grounding rules (do not violate)
- Every factual claim (names, dates, numbers, quotes, cause-and-effect) must be directly supported by
  the source material. Do not add, embellish, or "round up" facts that aren't there.
- If the source material is ambiguous, incomplete, or conflicting on a point, say so plainly or omit
  the point -- do not resolve the gap by inventing specifics.
- Do not invent quotes, statistics, or named individuals that do not appear in the source material.
- Vivid language, framing, and narrative structure are encouraged; invented facts are not. When in
  doubt, prefer a true, less dramatic sentence over a false, more dramatic one.

# Voice and style (make it compelling, not dry)
- Hook readers in the first two sentences -- lead with the most striking, human, or surprising detail
  from the source material, not with dynasties/dates/background first.
- Write like a smart friend explaining something fascinating, not like an encyclopedia: short,
  punchy sentences mixed with longer ones; active voice; concrete imagery over abstract summary.
- Connect the past to something the reader recognizes today where the source material supports it
  (e.g. scale, ambition, betrayal, innovation) -- but only draw comparisons that follow from the
  actual facts, never a forced or inaccurate one.
- Avoid textbook filler phrases ("played a significant role in", "it is important to note that").
- Each section heading should tease what's interesting about that section, not just label a topic.

# Structure
- Compelling, specific title (not generic, not clickbait that oversells beyond the facts)
- A 2-3 sentence summary that captures the hook, not just a topic restatement
- 4-6 sections, each with a heading and substantial Markdown-formatted content -- aim for
  roughly 300-450 words per section, not a couple of short paragraphs each.
- STRICT LENGTH REQUIREMENT: the article body (all sections combined) must land between 1500
  and 2000 words total -- this is a hard requirement in BOTH directions, not just a ceiling.
  Under 1500 words is just as much a failure as over 2000: it will be automatically rejected
  either way. If you're unsure whether you've written enough, add more concrete detail, examples,
  or context from the source material to each section rather than stopping early -- do not treat
  concision as a virtue here. Count roughly as you go and keep expanding sections that are thin.
- Provide 3-6 relevant lowercase, hyphenated tags (e.g. "mauryan-empire", "ancient-india")

# Source material
{source_text}

# Output format
Respond with ONLY a JSON object (no markdown code fences, no extra commentary) matching exactly this shape:
{{
  "title": "...",
  "summary": "...",
  "sections": [
    {{"heading": "...", "content": "..."}}
  ],
  "tags": ["...", "..."]
}}"""


class ArticleGenerationError(Exception):
    """Raised when the LLM response can't be parsed into a valid article."""


class ArticleGenerator:
    """Generates a curated Article from scraped source content using an LLM."""

    def __init__(self, llm_provider: LLMProvider | None = None):
        self.llm_provider = llm_provider or get_llm_provider()

    async def generate_article(
        self,
        scraped_content: list[ScrapedContent],
        topic: str,
        sequence: int = 1,
    ) -> Article:
        """
        Generate a structured Article from scraped source content.

        Args:
            scraped_content: Raw content scraped from one or more sources.
            topic: The topic that was scraped (used for the prompt and id).
            sequence: Sequence number for today's article id (art_YYYYMMDD_NNN).
                      Defaults to 1; multi-article-per-day sequencing is a
                      Phase 4 (scheduler) concern, not handled here.

        Returns:
            A fully populated Article, ready for validation/storage.

        Raises:
            ArticleGenerationError: If scraped_content is empty, or the LLM
                response can't be parsed into the expected shape.
        """
        if not scraped_content:
            raise ArticleGenerationError(
                f"Cannot generate an article for '{topic}' with no scraped content"
            )

        prompt = self._build_prompt(scraped_content, topic)
        # Generous ceiling, not a cost driver (billed on actual usage) -- needs
        # headroom beyond the ~2000-word article itself since extended-thinking
        # -capable models (e.g. claude-sonnet-5) spend part of this budget on
        # internal reasoning before producing the final JSON.
        raw_response = await self.llm_provider.generate_text(prompt, max_tokens=8000)
        parsed = self._parse_llm_response(raw_response)

        sections = self._build_sections(parsed)
        content = "\n\n".join(f"## {s.heading}\n\n{s.content}" for s in sections)
        word_count = len(content.split())

        publication_date = date.today()
        return Article(
            id=f"art_{publication_date.strftime('%Y%m%d')}_{sequence:03d}",
            title=parsed["title"],
            summary=parsed["summary"],
            content=content,
            sections=sections,
            citations=self._build_citations(scraped_content),
            publication_date=publication_date,
            reading_time_minutes=max(1, round(word_count / WORDS_PER_MINUTE)),
            tags=list(parsed.get("tags", [])),
        )

    def _build_prompt(self, scraped_content: list[ScrapedContent], topic: str) -> str:
        # Give each source a fair, even share of the character budget rather than
        # truncating the concatenated whole -- otherwise one oversized source (e.g. a
        # long but tangential Wikipedia page) can silently crowd out every other
        # source's content entirely, even when those sources are more on-topic.
        per_source_budget = max(1, MAX_SOURCE_CHARS // len(scraped_content))
        source_text = "\n\n".join(
            f"--- Source: {c.source_url} ---\n{c.raw_text[:per_source_budget]}"
            for c in scraped_content
        )
        return PROMPT_TEMPLATE.format(topic=topic, source_text=source_text)

    def _parse_llm_response(self, raw_response: str) -> dict:
        text = raw_response.strip()
        # LLMs frequently wrap JSON in markdown code fences despite instructions not to.
        if text.startswith("```"):
            text = text.strip("`")
            if text.startswith("json"):
                text = text[len("json"):]
            text = text.strip()

        # json_repair tolerates the malformed-but-recoverable JSON LLMs commonly
        # produce in prose-heavy responses (unescaped quotes/newlines inside
        # string values, trailing commas, etc.) instead of failing outright on
        # the first minor escaping mistake. On genuinely non-JSON input it
        # returns '' rather than raising, hence the explicit dict check below.
        parsed = json_repair.loads(text)
        if not isinstance(parsed, dict):
            raise ArticleGenerationError(
                f"LLM response was not valid JSON: {raw_response[:500]}"
            )

        missing = [
            field for field in ("title", "summary", "sections")
            if not parsed.get(field)
        ]
        if missing:
            raise ArticleGenerationError(
                f"LLM response missing required field(s): {missing}"
            )
        return parsed

    def _build_sections(self, parsed: dict) -> list[Section]:
        sections = []
        for order, raw_section in enumerate(parsed["sections"], start=1):
            if "heading" not in raw_section or "content" not in raw_section:
                raise ArticleGenerationError(
                    f"Section missing heading/content: {raw_section}"
                )
            sections.append(
                Section(
                    heading=raw_section["heading"],
                    content=raw_section["content"],
                    order=order,
                )
            )
        return sections

    def _build_citations(self, scraped_content: list[ScrapedContent]) -> list[Citation]:
        # Sources can return the same URL more than once (e.g. duplicate search
        # results); dedupe so the article doesn't cite the same page twice.
        seen_urls: set[str] = set()
        citations = []
        for c in scraped_content:
            if c.source_url in seen_urls:
                continue
            seen_urls.add(c.source_url)
            citations.append(
                Citation(
                    text=c.title,
                    source_url=c.source_url,
                    source_name=c.metadata.get("source", "Unknown"),
                    accessed_date=c.scraped_at or datetime.now(timezone.utc),
                )
            )
        return citations
