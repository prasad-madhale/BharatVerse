"""
LLM-powered editorial review for generated articles.

ContentValidator checks structure (word count, section count, citation count); this checks
what it explicitly can't: whether the article's claims are actually grounded in the scraped
source material, whether its citations support the claims near them, and whether it reads
as neutral, well-structured history writing rather than an embellished retelling.
"""

import logging
from typing import Literal

import json_repair
from pydantic import BaseModel, Field

from common.llm_provider import LLMProvider, get_llm_provider
from common.models import Article
from scrapper.models.article import ScrapedContent
from scrapper.source_text import build_source_text

logger = logging.getLogger(__name__)

CRITIC_PROMPT_TEMPLATE = """# Role
You are an editor for BharatVerse reviewing a drafted history article (topic: "{topic}") before
publication, the way a working editor at a history encyclopedia reviews a piece before it runs:
checking it against its sources, not just checking that it reads well.

# What to check, in priority order
1. **Grounding (most important, but do not confuse this with paraphrasing).** A specific,
   checkable fact -- a name, date, number, quote, or cause-and-effect claim -- must be
   supported by the source material below. Describing the same fact in different, more vivid
   words is NOT a grounding problem; that is normal writing, not invention. Only flag a claim
   when it adds information the source does not contain: a number, name, date, or causal link
   that isn't there or can't be reasonably inferred, or a specific-sounding detail invented to
   make a vague statement sound precise. A fair paraphrase, a reasonable inference the source
   clearly supports, or a synonym for a word the source used is never a grounding issue --
   judge whether the *fact* survived, not whether the *wording* matches.
2. **Citation relevance.** The citations listed should plausibly support the claims made near
   them, not just exist as a generic source list.
3. **Neutrality.** No nationalist, communal, or religious-bias framing. This matters
   specifically for Indian history, where that framing is a well-known risk.
4. **Contested claims.** Something historians actually debate should not be stated as settled
   fact without a hedge ("some historians believe...", "accounts differ on...").
5. **Structure.** A real introduction, developed body, and conclusion -- not just three
   sections in a row with no arc.
6. **Readability.** Should read like a smart friend explaining something fascinating, not a
   textbook -- but never at the cost of accuracy.

# How to score
Rate each issue you find `major` or `minor`. Reserve `major` for: a claim that adds a fact,
number, name or date the source doesn't contain or support; a citation that doesn't support
the claim it's attached to; biased framing; or a contested claim presented as settled fact.
Reworded, condensed, or more vividly phrased versions of a source fact are not issues at all --
do not list them, even as minor. Everything else -- style, phrasing, minor structural
roughness -- is `minor` at most.

**Most well-sourced drafts should be approved.** Approve the article if it has no `major`
issues, even if it has `minor` notes -- list those as notes for future polish, not blockers.
Before marking anything `major`, check the source material again for a paraphrase or a
reasonable inference you might have missed; when genuinely unsure whether a claim is grounded,
call it `minor`, not `major`. The goal is catching real invented facts, not enforcing verbatim
wording.

# Draft under review
## {title}
{summary}

{sections}

# Citations
{citations}

# Source material (what the draft must be grounded in)
{source_text}

# Output format
Respond with ONLY a JSON object (no markdown code fences, no extra commentary) matching
exactly this shape:
{{
  "approved": true or false,
  "summary": "one sentence verdict",
  "issues": [
    {{"category": "grounding|citation_relevance|neutrality|contested_claims|structure|readability",
      "severity": "major|minor", "location": "a section heading, or \\"overall\\"",
      "detail": "what's wrong, specifically", "suggestion": "a concrete fix"}}
  ]
}}"""


class CriticReviewError(Exception):
    """Raised when the critic's LLM response can't be parsed into a review."""


class CriticIssue(BaseModel):
    """One thing the critic flagged in a draft."""

    category: Literal[
        "grounding", "citation_relevance", "neutrality", "contested_claims", "structure", "readability"
    ] = Field(..., description="Which rubric item this issue is about")
    severity: Literal["major", "minor"] = Field(..., description="major blocks approval; minor is a note")
    location: str = Field(..., description="The section heading this applies to, or 'overall'")
    detail: str = Field(..., description="What's wrong, specific enough to act on")
    suggestion: str = Field(..., description="A concrete fix a revision can implement")


class CriticReview(BaseModel):
    """The critic's verdict on one draft."""

    approved: bool = Field(..., description="True if the article has no major issues")
    summary: str = Field(..., description="One-line verdict, for logs")
    issues: list[CriticIssue] = Field(default_factory=list)


def critic_metrics(review: CriticReview, rounds: int) -> dict:
    """What the scheduler logs about a critic loop, alongside article_metrics()."""
    return {
        "critic_rounds": rounds,
        "critic_approved": review.approved,
        "critic_issue_categories": [issue.category for issue in review.issues],
    }


class ArticleCritic:
    """Reviews a generated Article against its source material for an ArticleGenerator to revise."""

    def __init__(self, llm_provider: LLMProvider | None = None):
        self.llm_provider = llm_provider or get_llm_provider()

    async def review(self, article: Article, scraped_content: list[ScrapedContent], topic: str) -> CriticReview:
        """
        Review a drafted article against the source material it was generated from.

        Raises:
            CriticReviewError: If the LLM response can't be parsed into a review.
        """
        prompt = self._build_prompt(article, scraped_content, topic)
        # The review itself is compact JSON, but an extended-thinking model (e.g. claude-sonnet-5)
        # spends part of this budget on internal reasoning before producing it -- measured against a
        # real ~1000-word article and its full source text, thinking alone used ~5,500 of 8,000
        # tokens; 4,000 was not enough and returned no text at all (see article_generator.py, whose
        # generation call needs the same headroom).
        raw_response = await self.llm_provider.generate_text(prompt, max_tokens=8000)
        return self._parse_llm_response(raw_response)

    def _build_prompt(self, article: Article, scraped_content: list[ScrapedContent], topic: str) -> str:
        sections = "\n\n".join(f"## {s.heading}\n\n{s.content}" for s in article.sections)
        citations = "\n".join(f"- {c.text} ({c.source_url})" for c in article.citations) or "(none)"
        return CRITIC_PROMPT_TEMPLATE.format(
            topic=topic,
            title=article.title,
            summary=article.summary,
            sections=sections,
            citations=citations,
            source_text=build_source_text(scraped_content),
        )

    def _parse_llm_response(self, raw_response: str) -> CriticReview:
        text = raw_response.strip()
        # LLMs frequently wrap JSON in markdown code fences despite instructions not to.
        if text.startswith("```"):
            text = text.strip("`")
            if text.startswith("json"):
                text = text[len("json"):]
            text = text.strip()

        parsed = json_repair.loads(text)
        if not isinstance(parsed, dict) or "approved" not in parsed:
            raise CriticReviewError(f"Critic response was not a valid review: {raw_response[:500]}")

        try:
            return CriticReview(**parsed)
        except Exception as e:
            raise CriticReviewError(f"Critic response did not match the expected shape: {e}") from e
