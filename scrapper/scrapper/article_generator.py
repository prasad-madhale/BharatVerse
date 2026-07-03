"""
LLM-powered article generation for the BharatVerse content pipeline.

Turns raw ScrapedContent into a structured, citable Article by prompting
an LLM (via common.llm_provider) for the creative parts (title, summary,
sections, tags) while this module derives everything else -- citations,
reading time, content assembly -- directly from the scraped source data
rather than trusting the LLM to produce it accurately.
"""

import json
import logging
from datetime import date, datetime, timezone

from common.llm_provider import LLMProvider, get_llm_provider
from common.models import Article, Citation, Section
from scrapper.models.article import ScrapedContent

logger = logging.getLogger(__name__)

# Rough words-per-minute reading speed used to derive reading_time_minutes.
# Chosen so the BRD's stated 1500-2500 word target maps to ~10-15 minutes.
WORDS_PER_MINUTE = 150

# Cap on how much scraped source text is sent to the LLM per generation call.
MAX_SOURCE_CHARS = 15000

PROMPT_TEMPLATE = """You are a historical content curator specializing in Indian history.

Transform the following scraped source material into an engaging historical article for a general audience.

Requirements:
- Compelling, specific title (not generic)
- A 2-3 sentence summary
- Structure the article into 4-6 sections, each with a heading and Markdown-formatted content
- STRICT LIMIT: the article body (all sections combined) must be between 1500 and 2000 words
  total. Do not exceed 2000 words under any circumstances -- prioritize depth over breadth of
  coverage to stay within this limit.
- Use accessible language; focus on factual accuracy and historical context
- Do not fabricate facts that aren't supported by the source material
- Provide 3-6 relevant lowercase, hyphenated tags (e.g. "mauryan-empire", "ancient-india")

Source material (topic: "{topic}"):
{source_text}

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
        raw_response = await self.llm_provider.generate_text(prompt, max_tokens=4000)
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
        source_text = "\n\n".join(
            f"--- Source: {c.source_url} ---\n{c.raw_text}" for c in scraped_content
        )
        if len(source_text) > MAX_SOURCE_CHARS:
            source_text = source_text[:MAX_SOURCE_CHARS]
        return PROMPT_TEMPLATE.format(topic=topic, source_text=source_text)

    def _parse_llm_response(self, raw_response: str) -> dict:
        text = raw_response.strip()
        # LLMs frequently wrap JSON in markdown code fences despite instructions not to.
        if text.startswith("```"):
            text = text.strip("`")
            if text.startswith("json"):
                text = text[len("json"):]
            text = text.strip()

        try:
            parsed = json.loads(text)
        except json.JSONDecodeError as e:
            raise ArticleGenerationError(
                f"LLM response was not valid JSON: {e}\nResponse was: {raw_response[:500]}"
            ) from e

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
