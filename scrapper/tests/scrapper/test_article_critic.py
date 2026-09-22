"""
Unit tests for ArticleCritic.

Tests prompt construction and LLM response parsing with a mocked LLM
provider (no real API calls).
"""

import json
from datetime import date, datetime, timezone

import pytest

from scrapper.article_critic import ArticleCritic, CriticReviewError
from scrapper.models.article import ScrapedContent
from common.models import Article, Citation, Section

APPROVED_RESPONSE = json.dumps({
    "approved": True,
    "summary": "Well-grounded and neutral.",
    "issues": [],
})

REJECTED_RESPONSE = json.dumps({
    "approved": False,
    "summary": "Contains an unsupported claim.",
    "issues": [
        {
            "category": "grounding",
            "severity": "major",
            "location": "Origins",
            "detail": "The draft states the empire had '600,000 soldiers', a figure not in the source material.",
            "suggestion": "Remove the figure or attribute it to a named source if one exists.",
        }
    ],
})


class FakeLLMProvider:
    """Minimal stand-in for common.llm_provider.LLMProvider."""

    def __init__(self, response: str):
        self.response = response
        self.last_prompt = None

    async def generate_text(self, prompt: str, max_tokens: int = 4000) -> str:
        self.last_prompt = prompt
        return self.response


def make_article(title="The Rise of the Mauryan Empire"):
    return Article(
        id="art_20260101_001",
        title=title,
        summary="A look at how Chandragupta Maurya unified much of India.",
        content="## Origins\n\nThe Mauryan Empire began through conquest.",
        sections=[Section(heading="Origins", content="The Mauryan Empire began through conquest.", order=1)],
        citations=[
            Citation(
                text="Mauryan Empire", source_url="https://en.wikipedia.org/wiki/Mauryan_Empire",
                source_name="wikipedia", accessed_date=datetime(2026, 1, 1, tzinfo=timezone.utc),
            )
        ],
        publication_date=date(2026, 1, 1),
        reading_time_minutes=10,
    )


def make_scraped_content():
    return ScrapedContent(
        source_url="https://en.wikipedia.org/wiki/Mauryan_Empire",
        title="Mauryan Empire",
        raw_text="The Mauryan Empire was a geographically extensive empire founded through conquest.",
        images=[],
        metadata={"source": "wikipedia"},
        scraped_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )


class TestReview:
    @pytest.mark.asyncio
    async def test_approves_a_well_grounded_article(self):
        critic = ArticleCritic(llm_provider=FakeLLMProvider(APPROVED_RESPONSE))

        review = await critic.review(make_article(), [make_scraped_content()], topic="Mauryan Empire")

        assert review.approved is True
        assert review.issues == []

    @pytest.mark.asyncio
    async def test_rejects_with_a_major_grounding_issue(self):
        critic = ArticleCritic(llm_provider=FakeLLMProvider(REJECTED_RESPONSE))

        review = await critic.review(make_article(), [make_scraped_content()], topic="Mauryan Empire")

        assert review.approved is False
        assert len(review.issues) == 1
        assert review.issues[0].category == "grounding"
        assert review.issues[0].severity == "major"
        assert "600,000 soldiers" in review.issues[0].detail

    @pytest.mark.asyncio
    async def test_strips_markdown_code_fences_from_response(self):
        fenced_response = f"```json\n{APPROVED_RESPONSE}\n```"
        critic = ArticleCritic(llm_provider=FakeLLMProvider(fenced_response))

        review = await critic.review(make_article(), [make_scraped_content()], topic="Mauryan Empire")

        assert review.approved is True

    @pytest.mark.asyncio
    async def test_raises_on_invalid_json_response(self):
        critic = ArticleCritic(llm_provider=FakeLLMProvider("not json at all"))

        with pytest.raises(CriticReviewError):
            await critic.review(make_article(), [make_scraped_content()], topic="Mauryan Empire")

    @pytest.mark.asyncio
    async def test_raises_on_missing_approved_field(self):
        incomplete = json.dumps({"summary": "no verdict given"})
        critic = ArticleCritic(llm_provider=FakeLLMProvider(incomplete))

        with pytest.raises(CriticReviewError):
            await critic.review(make_article(), [make_scraped_content()], topic="Mauryan Empire")

    @pytest.mark.asyncio
    async def test_raises_on_malformed_issue(self):
        malformed = json.dumps({
            "approved": False,
            "summary": "bad",
            "issues": [{"category": "not-a-real-category", "severity": "major", "location": "x",
                        "detail": "x", "suggestion": "x"}],
        })
        critic = ArticleCritic(llm_provider=FakeLLMProvider(malformed))

        with pytest.raises(CriticReviewError):
            await critic.review(make_article(), [make_scraped_content()], topic="Mauryan Empire")

    @pytest.mark.asyncio
    async def test_prompt_includes_topic_article_and_source_text(self):
        llm = FakeLLMProvider(APPROVED_RESPONSE)
        critic = ArticleCritic(llm_provider=llm)

        await critic.review(make_article(), [make_scraped_content()], topic="Mauryan Empire")

        assert "Mauryan Empire" in llm.last_prompt
        assert "The Rise of the Mauryan Empire" in llm.last_prompt
        assert "geographically extensive empire founded through conquest" in llm.last_prompt

    @pytest.mark.asyncio
    async def test_defaults_to_shared_llm_provider_singleton(self, monkeypatch):
        fake = FakeLLMProvider(APPROVED_RESPONSE)
        monkeypatch.setattr("scrapper.article_critic.get_llm_provider", lambda: fake)

        critic = ArticleCritic()

        assert critic.llm_provider is fake
