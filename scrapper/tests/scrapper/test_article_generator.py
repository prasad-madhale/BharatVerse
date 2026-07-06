"""
Unit tests for ArticleGenerator.

Tests prompt construction, LLM response parsing, and article assembly
with a mocked LLM provider (no real API calls).
"""

import json
from datetime import date, datetime, timezone

import pytest

from scrapper.article_generator import ArticleGenerationError, ArticleGenerator
from scrapper.models.article import ScrapedContent

VALID_LLM_RESPONSE = json.dumps({
    "title": "The Rise of the Mauryan Empire",
    "summary": "A look at how Chandragupta Maurya unified much of India.",
    "sections": [
        {"heading": "Origins", "content": "The Mauryan Empire began " + ("word " * 800)},
        {"heading": "Legacy", "content": "Its legacy shaped India " + ("word " * 800)},
    ],
    "tags": ["mauryan-empire", "ancient-india"],
})


def make_scraped_content(source_url="https://en.wikipedia.org/wiki/Mauryan_Empire", source="wikipedia"):
    return ScrapedContent(
        source_url=source_url,
        title="Mauryan Empire",
        raw_text="The Mauryan Empire was a geographically extensive empire in ancient India.",
        images=[],
        metadata={"source": source},
        scraped_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )


class FakeLLMProvider:
    """Minimal stand-in for common.llm_provider.LLMProvider."""

    def __init__(self, response: str):
        self.response = response
        self.last_prompt = None

    async def generate_text(self, prompt: str, max_tokens: int = 4000) -> str:
        self.last_prompt = prompt
        return self.response


class TestGenerateArticle:
    @pytest.mark.asyncio
    async def test_generates_article_from_valid_response(self):
        generator = ArticleGenerator(llm_provider=FakeLLMProvider(VALID_LLM_RESPONSE))
        scraped = [make_scraped_content()]

        article = await generator.generate_article(scraped, topic="Mauryan Empire")

        assert article.title == "The Rise of the Mauryan Empire"
        assert article.summary.startswith("A look at how Chandragupta")
        assert len(article.sections) == 2
        assert article.sections[0].order == 1
        assert article.sections[1].order == 2
        assert "Origins" in article.content
        assert "Legacy" in article.content
        assert article.tags == ["mauryan-empire", "ancient-india"]
        assert article.publication_date == date.today()
        assert article.id == f"art_{date.today().strftime('%Y%m%d')}_001"

    @pytest.mark.asyncio
    async def test_reading_time_derived_from_word_count(self):
        generator = ArticleGenerator(llm_provider=FakeLLMProvider(VALID_LLM_RESPONSE))
        article = await generator.generate_article([make_scraped_content()], topic="Mauryan Empire")

        # ~1600 words of content -> reading_time_minutes should be > 0 and roughly proportional
        assert article.reading_time_minutes >= 1

    @pytest.mark.asyncio
    async def test_citations_built_from_scraped_content_not_llm(self):
        generator = ArticleGenerator(llm_provider=FakeLLMProvider(VALID_LLM_RESPONSE))
        scraped = [
            make_scraped_content("https://en.wikipedia.org/wiki/X", "wikipedia"),
            make_scraped_content("https://archive.org/details/Y", "archive_org"),
        ]

        article = await generator.generate_article(scraped, topic="X")

        assert len(article.citations) == 2
        assert article.citations[0].source_url == "https://en.wikipedia.org/wiki/X"
        assert article.citations[0].source_name == "wikipedia"
        assert article.citations[1].source_url == "https://archive.org/details/Y"
        assert article.citations[1].source_name == "archive_org"

    @pytest.mark.asyncio
    async def test_deduplicates_citations_with_same_source_url(self):
        generator = ArticleGenerator(llm_provider=FakeLLMProvider(VALID_LLM_RESPONSE))
        scraped = [
            make_scraped_content("https://en.wikipedia.org/wiki/Dup", "wikipedia"),
            make_scraped_content("https://en.wikipedia.org/wiki/Dup", "wikipedia"),
        ]

        article = await generator.generate_article(scraped, topic="Dup")

        assert len(article.citations) == 1
        assert article.citations[0].source_url == "https://en.wikipedia.org/wiki/Dup"

    @pytest.mark.asyncio
    async def test_strips_markdown_code_fences_from_response(self):
        fenced_response = f"```json\n{VALID_LLM_RESPONSE}\n```"
        generator = ArticleGenerator(llm_provider=FakeLLMProvider(fenced_response))

        article = await generator.generate_article([make_scraped_content()], topic="Mauryan Empire")

        assert article.title == "The Rise of the Mauryan Empire"

    @pytest.mark.asyncio
    async def test_sequence_number_used_in_id(self):
        generator = ArticleGenerator(llm_provider=FakeLLMProvider(VALID_LLM_RESPONSE))

        article = await generator.generate_article([make_scraped_content()], topic="Mauryan Empire", sequence=7)

        assert article.id == f"art_{date.today().strftime('%Y%m%d')}_007"

    @pytest.mark.asyncio
    async def test_raises_on_empty_scraped_content(self):
        generator = ArticleGenerator(llm_provider=FakeLLMProvider(VALID_LLM_RESPONSE))

        with pytest.raises(ArticleGenerationError, match="no scraped content"):
            await generator.generate_article([], topic="Mauryan Empire")

    @pytest.mark.asyncio
    async def test_raises_on_invalid_json_response(self):
        generator = ArticleGenerator(llm_provider=FakeLLMProvider("not json at all"))

        with pytest.raises(ArticleGenerationError, match="not valid JSON"):
            await generator.generate_article([make_scraped_content()], topic="Mauryan Empire")

    @pytest.mark.asyncio
    async def test_raises_on_missing_required_fields(self):
        incomplete = json.dumps({"title": "Only a title"})
        generator = ArticleGenerator(llm_provider=FakeLLMProvider(incomplete))

        with pytest.raises(ArticleGenerationError, match="missing required field"):
            await generator.generate_article([make_scraped_content()], topic="Mauryan Empire")

    @pytest.mark.asyncio
    async def test_raises_on_malformed_section(self):
        malformed = json.dumps({
            "title": "Title",
            "summary": "Summary",
            "sections": [{"heading": "Only heading, no content"}],
        })
        generator = ArticleGenerator(llm_provider=FakeLLMProvider(malformed))

        with pytest.raises(ArticleGenerationError, match="Section missing"):
            await generator.generate_article([make_scraped_content()], topic="Mauryan Empire")

    @pytest.mark.asyncio
    async def test_prompt_includes_topic_and_source_text(self):
        llm = FakeLLMProvider(VALID_LLM_RESPONSE)
        generator = ArticleGenerator(llm_provider=llm)

        await generator.generate_article([make_scraped_content()], topic="Mauryan Empire")

        assert "Mauryan Empire" in llm.last_prompt
        assert "geographically extensive empire" in llm.last_prompt

    @pytest.mark.asyncio
    async def test_prompt_gives_each_source_a_fair_share_of_the_char_budget(self):
        # Regression test: a single oversized source used to be able to consume the
        # entire MAX_SOURCE_CHARS budget via naive concatenate-then-truncate,
        # silently dropping every other source's content from the prompt.
        from scrapper.article_generator import MAX_SOURCE_CHARS

        oversized = make_scraped_content(
            source_url="https://en.wikipedia.org/wiki/Some_Unrelated_Long_Page",
            source="wikipedia",
        )
        oversized.raw_text = "x" * (MAX_SOURCE_CHARS * 2)

        distinctive_marker = "THIS_IS_THE_SECOND_SOURCE_CONTENT"
        second_source = make_scraped_content(
            source_url="https://www.newworldencyclopedia.org/entry/Some_Topic",
            source="new_world_encyclopedia",
        )
        second_source.raw_text = distinctive_marker

        llm = FakeLLMProvider(VALID_LLM_RESPONSE)
        generator = ArticleGenerator(llm_provider=llm)

        await generator.generate_article([oversized, second_source], topic="Some Topic")

        assert distinctive_marker in llm.last_prompt

    @pytest.mark.asyncio
    async def test_defaults_to_shared_llm_provider_singleton(self, monkeypatch):
        fake = FakeLLMProvider(VALID_LLM_RESPONSE)
        monkeypatch.setattr("scrapper.article_generator.get_llm_provider", lambda: fake)

        generator = ArticleGenerator()

        assert generator.llm_provider is fake
