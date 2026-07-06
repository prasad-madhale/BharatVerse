"""
LLM-powered topic selection for the BharatVerse content pipeline.

Asks an LLM (via common.llm_provider) to propose fresh, well-documented
Indian history topics, explicitly avoiding anything already published, so
the daily scheduler doesn't need a hand-curated topic list.
"""

import logging

import json_repair

from common.llm_provider import LLMProvider, get_llm_provider

logger = logging.getLogger(__name__)

PROMPT_TEMPLATE = """# Role
You are a topic curator for BharatVerse, an app that publishes one Indian history article per day
for a curious, time-poor general audience.

# Task
Propose {count} distinct topic(s) for upcoming articles. Each topic should be a specific person,
dynasty, event, monument, or movement in Indian history that is well-documented on Wikipedia (i.e.
has enough verifiable material for a grounded ~1500-2000 word article -- avoid obscure topics with
only a few sentences of coverage anywhere).

# Rules
- Do not propose any topic that duplicates or substantially overlaps with anything in this list of
  already-published topics: {excluded}
- Vary era and theme across the {count} topic(s) if more than one is requested (do not propose
  several topics from the same dynasty/decade back to back).
- Each topic must be specific enough to scope a single article (e.g. "Battle of Plassey", not
  "British colonialism in India").
- CRITICAL: each topic must be a short, plain phrase that exactly matches (or is very close to) the
  likely title of its own Wikipedia article -- since it's used verbatim as a search query. Use the
  canonical name only: "Ashoka" not "Ashoka the Great: From Conqueror to Dharma King"; "Battle of
  Plassey" not "The Battle That Changed India Forever: Plassey 1757". Never include a colon, a
  subtitle, or narrative framing in the topic string itself -- save the storytelling for the article
  the topic will later be turned into, not the topic string.

# Output format
Respond with ONLY a JSON array of strings (no markdown code fences, no extra commentary), e.g.:
["Topic One", "Topic Two"]"""


class TopicGenerationError(Exception):
    """Raised when the LLM response can't be parsed into a valid topic list."""


class TopicGenerator:
    """Proposes fresh article topics using an LLM, avoiding already-published ones."""

    def __init__(self, llm_provider: LLMProvider | None = None):
        self.llm_provider = llm_provider or get_llm_provider()

    async def generate_topics(self, count: int, exclude_titles: list[str]) -> list[str]:
        """
        Propose `count` fresh topics, avoiding anything in `exclude_titles`.

        Args:
            count: Number of topics to propose.
            exclude_titles: Titles of already-published articles to avoid repeating.

        Returns:
            A list of `count` topic strings.

        Raises:
            TopicGenerationError: If the LLM response can't be parsed into the
                expected shape, or doesn't contain enough topics.
        """
        prompt = self._build_prompt(count, exclude_titles)
        raw_response = await self.llm_provider.generate_text(prompt, max_tokens=1000)
        topics = self._parse_llm_response(raw_response)

        if len(topics) < count:
            raise TopicGenerationError(
                f"Requested {count} topic(s) but LLM returned {len(topics)}: {topics}"
            )
        return topics[:count]

    def _build_prompt(self, count: int, exclude_titles: list[str]) -> str:
        excluded = ", ".join(exclude_titles) if exclude_titles else "(none yet)"
        return PROMPT_TEMPLATE.format(count=count, excluded=excluded)

    def _parse_llm_response(self, raw_response: str) -> list[str]:
        text = raw_response.strip()
        # LLMs frequently wrap JSON in markdown code fences despite instructions not to.
        if text.startswith("```"):
            text = text.strip("`")
            if text.startswith("json"):
                text = text[len("json"):]
            text = text.strip()

        # json_repair tolerates the malformed-but-recoverable JSON LLMs commonly
        # produce (unescaped quotes/newlines inside string values, trailing
        # commas, etc.) instead of failing outright on the first minor escaping
        # mistake. On genuinely non-JSON input it returns '' rather than
        # raising, which the isinstance check in the caller below handles.
        parsed = json_repair.loads(text)

        if not isinstance(parsed, list) or not all(isinstance(t, str) and t.strip() for t in parsed):
            raise TopicGenerationError(
                f"LLM response was not a JSON array of non-empty strings: {parsed}"
            )
        return parsed
