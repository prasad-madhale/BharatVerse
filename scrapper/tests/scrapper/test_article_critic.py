"""
Unit tests for ArticleCritic.

Tests prompt construction and LLM response parsing with a mocked LLM
provider (no real API calls).
"""

import json
from datetime import date, datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from scrapper.article_critic import ArticleCritic, CriticReviewError
from scrapper.models.article import ScrapedContent
from common.models import Article, ArticleImage, Citation, Section

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
        self.last_effort = None

    async def generate_text(self, prompt: str, max_tokens: int = 4000, effort: str | None = None) -> str:
        self.last_prompt = prompt
        self.last_effort = effort
        return self.response


class FakeVisionLLMProvider:
    """Records every generate_text_with_image call; responses is consumed one-per-call, or a
    single response is reused for every call if only one was given."""

    def __init__(self, responses):
        self.responses = list(responses) if isinstance(responses, list) else None
        self.single_response = None if self.responses is not None else responses
        self.calls = []

    async def generate_text_with_image(self, prompt, image_bytes, media_type, effort=None):
        self.calls.append((prompt, image_bytes, media_type, effort))
        if self.responses is not None:
            return self.responses.pop(0)
        return self.single_response


def make_image(url="https://storage.example/0.jpg"):
    return ArticleImage(
        url=url, alt_text="a", credit="Someone via Wikimedia Commons",
        source_url="https://commons.wikimedia.org/wiki/File:X.jpg", license="CC BY-SA 4.0",
        width=1200, height=800,
    )


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
    async def test_caps_thinking_depth_for_this_structured_verdict_task(self):
        """A compact JSON verdict doesn't need open-ended exploratory reasoning --
        effort="medium" bounds it (see article_critic.py's review)."""
        llm = FakeLLMProvider(APPROVED_RESPONSE)
        critic = ArticleCritic(llm_provider=llm)

        await critic.review(make_article(), [make_scraped_content()], topic="Mauryan Empire")

        assert llm.last_effort == "medium"

    @pytest.mark.asyncio
    async def test_defaults_to_shared_llm_provider_singleton(self, monkeypatch):
        """Only used when neither CRITIC_LLM_PROVIDER nor CRITIC_LLM_MODEL is set -- settings is
        mocked explicitly (not left to read the real .env) so this doesn't depend on whether
        the developer's own .env happens to set either."""
        fake = FakeLLMProvider(APPROVED_RESPONSE)
        monkeypatch.setattr("scrapper.article_critic.get_llm_provider", lambda: fake)
        settings = MagicMock(
            critic_llm_provider=None, critic_llm_model=None,
            image_cohesion_llm_provider="ollama", image_cohesion_llm_model=None,
        )
        monkeypatch.setattr("scrapper.article_critic.get_llm_settings", lambda: settings)

        critic = ArticleCritic()

        assert critic.llm_provider is fake


COHESIVE = json.dumps({"cohesive": True, "reason": "Depicts the actual subject."})
NOT_COHESIVE = json.dumps({"cohesive": False, "reason": "Unrelated Buddha statue, not the battle."})


class TestReviewImageCohesion:
    @pytest.mark.asyncio
    async def test_no_issues_when_every_image_is_cohesive(self):
        vision = FakeVisionLLMProvider(COHESIVE)
        critic = ArticleCritic(llm_provider=FakeLLMProvider(""), image_llm_provider=vision)
        with patch.object(ArticleCritic, "_download", AsyncMock(return_value=b"fake-bytes")):
            issues = await critic.review_image_cohesion(
                make_article(), [make_image("https://s/0.jpg"), make_image("https://s/1.jpg")]
            )

        assert issues == []
        assert len(vision.calls) == 2

    @pytest.mark.asyncio
    async def test_one_issue_per_failing_image_naming_which_one(self):
        vision = FakeVisionLLMProvider([COHESIVE, NOT_COHESIVE])
        critic = ArticleCritic(llm_provider=FakeLLMProvider(""), image_llm_provider=vision)
        with patch.object(ArticleCritic, "_download", AsyncMock(return_value=b"fake-bytes")):
            issues = await critic.review_image_cohesion(
                make_article(), [make_image("https://s/0.jpg"), make_image("https://s/1.jpg")]
            )

        assert len(issues) == 1
        assert issues[0].category == "image_cohesion"
        assert issues[0].severity == "major"
        assert issues[0].location == "inline image 2"
        assert "Buddha statue" in issues[0].detail

    @pytest.mark.asyncio
    async def test_featured_image_is_named_distinctly_from_inline_ones(self):
        vision = FakeVisionLLMProvider(NOT_COHESIVE)
        critic = ArticleCritic(llm_provider=FakeLLMProvider(""), image_llm_provider=vision)
        with patch.object(ArticleCritic, "_download", AsyncMock(return_value=b"fake-bytes")):
            issues = await critic.review_image_cohesion(make_article(), [make_image()])

        assert issues[0].location == "featured image"  # short label, distinct from the prompt's phrasing

    @pytest.mark.asyncio
    async def test_empty_list_for_an_article_with_no_images(self):
        vision = FakeVisionLLMProvider(COHESIVE)
        critic = ArticleCritic(llm_provider=FakeLLMProvider(""), image_llm_provider=vision)

        issues = await critic.review_image_cohesion(make_article(), [])

        assert issues == []
        assert vision.calls == []

    @pytest.mark.asyncio
    async def test_fails_open_when_one_images_check_errors(self):
        """A download or LLM error on one image is skipped, not raised -- a cohesion-check
        hiccup must never block publication."""
        vision = FakeVisionLLMProvider(COHESIVE)
        critic = ArticleCritic(llm_provider=FakeLLMProvider(""), image_llm_provider=vision)
        download = AsyncMock(side_effect=[Exception("network error"), b"fake-bytes"])
        with patch.object(ArticleCritic, "_download", download):
            issues = await critic.review_image_cohesion(
                make_article(), [make_image("https://s/0.jpg"), make_image("https://s/1.jpg")]
            )

        assert issues == []  # the second (successfully-checked) image was cohesive
        assert len(vision.calls) == 1  # the first image never reached the LLM call at all

    @pytest.mark.asyncio
    async def test_prompt_includes_title_summary_and_image_role(self):
        vision = FakeVisionLLMProvider(COHESIVE)
        critic = ArticleCritic(llm_provider=FakeLLMProvider(""), image_llm_provider=vision)
        with patch.object(ArticleCritic, "_download", AsyncMock(return_value=b"fake-bytes")):
            await critic.review_image_cohesion(make_article(), [make_image()])

        prompt = vision.calls[0][0]
        assert "The Rise of the Mauryan Empire" in prompt
        assert "Chandragupta Maurya" in prompt
        assert "the featured image" in prompt
