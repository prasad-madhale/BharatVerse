"""
LLM-powered editorial review for generated articles.

ContentValidator checks structure (word count, section count, citation count); this checks
what it explicitly can't: whether the article's claims are actually grounded in the scraped
source material, whether its citations support the claims near them, and whether it reads
as neutral, well-structured history writing rather than an embellished retelling.
"""

import asyncio
import logging
from typing import Literal

import json_repair
import requests
from pydantic import BaseModel, Field

from common.config import get_llm_settings
from common.llm_provider import LLMProvider, get_llm_provider
from common.models import Article, ArticleImage
from scrapper.models.article import ScrapedContent
from scrapper.source_text import build_source_text

logger = logging.getLogger(__name__)

_MIME_BY_EXTENSION = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp"}

CRITIC_PROMPT_TEMPLATE = """<source_material>
{source_text}
</source_material>

<draft_under_review>
## {title}
{summary}

{sections}
</draft_under_review>

<citations>
{citations}
</citations>

<role>
You are an editor for BharatVerse reviewing the drafted history article above (topic: "{topic}")
before publication, the way a working editor at a history encyclopedia reviews a piece before it
runs: checking it against its sources, not just checking that it reads well.
</role>

<review_criteria>
Check the draft against the source material above, in this priority order:
1. Grounding (most important, but do not confuse this with paraphrasing). A specific, checkable
   fact -- a name, date, number, quote, or cause-and-effect claim -- must be supported by the
   source material. Describing the same fact in different, more vivid words is NOT a grounding
   problem; that is normal writing, not invention. Only flag a claim when it adds information the
   source does not contain: a number, name, date, or causal link that isn't there or can't be
   reasonably inferred, or a specific-sounding detail invented to make a vague statement sound
   precise. A fair paraphrase, a reasonable inference the source clearly supports, or a synonym
   for a word the source used is never a grounding issue -- judge whether the fact survived, not
   whether the wording matches.
2. Citation relevance. The citations listed should plausibly support the claims made near them,
   not just exist as a generic source list.
3. Neutrality. No nationalist, communal, or religious-bias framing. This matters specifically for
   Indian history, where that framing is a well-known risk.
4. Contested claims. Something historians actually debate should not be stated as settled fact
   without a hedge ("some historians believe...", "accounts differ on...").
5. Structure. A real introduction, developed body, and conclusion -- not just three sections in a
   row with no arc.
6. Readability. Should read like a smart friend explaining something fascinating, not a textbook
   -- but never at the cost of accuracy.
</review_criteria>

<scoring_guidance>
Rate each issue you find major or minor. Reserve major for: a claim that adds a fact, number,
name or date the source doesn't contain or support; a citation that doesn't support the claim
it's attached to; biased framing; or a contested claim presented as settled fact. Reworded,
condensed, or more vividly phrased versions of a source fact are not issues at all -- do not list
them, even as minor. Everything else -- style, phrasing, minor structural roughness -- is minor
at most.

Most well-sourced drafts should be approved. Approve the article if it has no major issues, even
if it has minor notes -- list those as notes for future polish, not blockers. Before marking
anything major, check the source material again for a paraphrase or a reasonable inference you
might have missed; when genuinely unsure whether a claim is grounded, call it minor, not major.
The goal is catching real invented facts, not enforcing verbatim wording.
</scoring_guidance>

<output_format>
Respond with only a JSON object matching exactly this shape. Do not include markdown code fences
or any text before or after the JSON.
{{
  "approved": true or false,
  "summary": "one sentence verdict",
  "issues": [
    {{"category": "grounding|citation_relevance|neutrality|contested_claims|structure|readability",
      "severity": "major|minor", "location": "a section heading, or \\"overall\\"",
      "detail": "what's wrong, specifically", "suggestion": "a concrete fix"}}
  ]
}}
</output_format>"""

IMAGE_COHESION_PROMPT_TEMPLATE = """You are an editor for BharatVerse checking whether an
article's image actually fits the piece before it runs -- a later, stricter look than the
sourcing step's own relevance check, which only guards against an obviously wrong keyword-search
result.

Article title: {title}
Article summary: {summary}

Does this image genuinely fit as {image_role} for this specific article -- not just "a photo of
India" or "old and historical-looking," but the actual place, person, object, era, or event the
piece is about? Be a reasonably strict editor: a generic or loosely-related image should be
flagged, not approved just because it isn't obviously wrong.

Respond with ONLY a JSON object, no markdown fences:
{{"cohesive": true or false, "reason": "one specific sentence"}}"""


class CriticReviewError(Exception):
    """Raised when the critic's LLM response can't be parsed into a review."""


class CriticIssue(BaseModel):
    """One thing the critic flagged in a draft."""

    category: Literal[
        "grounding", "citation_relevance", "neutrality", "contested_claims", "structure",
        "readability", "image_cohesion",
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

    def __init__(
        self, llm_provider: LLMProvider | None = None, image_llm_provider: LLMProvider | None = None
    ):
        settings = get_llm_settings()
        # settings.critic_llm_provider/_model default to None, which LLMProvider resolves to the
        # same provider/model generation uses -- set them to review with a different model.
        self.llm_provider = llm_provider or (
            get_llm_provider()
            if settings.critic_llm_provider is None and settings.critic_llm_model is None
            else LLMProvider(provider=settings.critic_llm_provider, model=settings.critic_llm_model)
        )
        # Separate provider for review_image_cohesion: defaults to a local, free, already
        # vision-capable model (settings.image_cohesion_llm_provider) rather than whatever paid
        # provider the text review above uses -- cohesion checks run once per image, per round.
        self.image_llm_provider = image_llm_provider or LLMProvider(
            provider=settings.image_cohesion_llm_provider, model=settings.image_cohesion_llm_model
        )

    async def review(
        self, article: Article, scraped_content: list[ScrapedContent], topic: str
    ) -> CriticReview:
        """
        Review a drafted article against the source material it was generated from.

        Raises:
            CriticReviewError: If the LLM response can't be parsed into a review.
        """
        prompt = self._build_prompt(article, scraped_content, topic)
        # The review itself is compact JSON, but claude-sonnet-5 runs adaptive thinking by
        # default and max_tokens caps thinking plus the response together -- measured against a
        # real ~1000-word article and its full source text, thinking alone used ~5,500 of 8,000
        # tokens, and a longer article's revision review has returned empty text entirely in
        # production. effort="medium" bounds thinking depth for this well-specified,
        # structured-verdict task (see llm_provider.py's generate_text docstring), and max_tokens
        # is raised well past the observed worst case for extra headroom.
        raw_response = await self.llm_provider.generate_text(prompt, max_tokens=16000, effort="medium")
        return self._parse_llm_response(raw_response)

    async def review_image_cohesion(self, article: Article, images: list[ArticleImage]) -> list[CriticIssue]:
        """
        Vision-checks every image (not just the featured one -- affordable to do generously
        since image_llm_provider defaults to a free local model) against the article, returning
        one issue per image that doesn't genuinely fit. Fails open per-image: a download or LLM
        error is logged and skipped rather than raised, since a cohesion-check hiccup must never
        block publication the way an unparseable review from review() does.
        """
        issues: list[CriticIssue] = []
        for index, image in enumerate(images):
            label = "featured image" if index == 0 else f"inline image {index + 1}"
            role = "the featured image" if index == 0 else f"an inline image ({label})"
            try:
                image_bytes = await self._download(image.url)
                prompt = IMAGE_COHESION_PROMPT_TEMPLATE.format(
                    title=article.title, summary=article.summary, image_role=role,
                )
                raw = await self.image_llm_provider.generate_text_with_image(
                    prompt, image_bytes, _guess_mime(image.url), effort="medium"
                )
                parsed = json_repair.loads(_strip_code_fence(raw))
                if isinstance(parsed, dict) and not parsed.get("cohesive", True):
                    issues.append(CriticIssue(
                        category="image_cohesion", severity="major", location=label,
                        detail=parsed.get("reason", "Image does not fit the article"),
                        suggestion="Source a different image",
                    ))
            except Exception:
                logger.warning(f"Image cohesion check failed for {label} ({image.url})", exc_info=True)
        return issues

    async def _download(self, url: str) -> bytes:
        def _fetch():
            response = requests.get(url, timeout=15)
            response.raise_for_status()
            return response.content
        return await asyncio.to_thread(_fetch)

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


def _guess_mime(url: str) -> str:
    extension = url.rsplit(".", 1)[-1].split("?", 1)[0].lower()
    return _MIME_BY_EXTENSION.get(extension, "image/jpeg")


def _strip_code_fence(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[len("json"):]
    return text.strip()
