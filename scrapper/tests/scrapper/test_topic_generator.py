"""
Unit tests for TopicGenerator.
"""

from unittest.mock import AsyncMock, MagicMock

import pytest

from scrapper.topic_generator import TopicGenerationError, TopicGenerator


def _make_generator(response_text: str) -> TopicGenerator:
    mock_provider = MagicMock()
    mock_provider.generate_text = AsyncMock(return_value=response_text)
    return TopicGenerator(llm_provider=mock_provider)


class TestGenerateTopics:
    async def test_returns_topics_from_valid_json_response(self):
        generator = _make_generator('["Battle of Plassey", "Rani Lakshmibai"]')

        topics = await generator.generate_topics(count=2, exclude_titles=[])

        assert topics == ["Battle of Plassey", "Rani Lakshmibai"]

    async def test_strips_markdown_code_fences(self):
        generator = _make_generator('```json\n["Battle of Plassey"]\n```')

        topics = await generator.generate_topics(count=1, exclude_titles=[])

        assert topics == ["Battle of Plassey"]

    async def test_truncates_to_requested_count(self):
        generator = _make_generator('["Topic A", "Topic B", "Topic C"]')

        topics = await generator.generate_topics(count=2, exclude_titles=[])

        assert topics == ["Topic A", "Topic B"]

    async def test_includes_exclude_titles_in_prompt(self):
        mock_provider = MagicMock()
        mock_provider.generate_text = AsyncMock(return_value='["New Topic"]')
        generator = TopicGenerator(llm_provider=mock_provider)

        await generator.generate_topics(count=1, exclude_titles=["Old Topic One", "Old Topic Two"])

        prompt_used = mock_provider.generate_text.call_args[0][0]
        assert "Old Topic One" in prompt_used
        assert "Old Topic Two" in prompt_used

    async def test_raises_when_llm_returns_fewer_topics_than_requested(self):
        generator = _make_generator('["Only One Topic"]')

        with pytest.raises(TopicGenerationError, match="Requested 2"):
            await generator.generate_topics(count=2, exclude_titles=[])

    async def test_raises_on_invalid_json(self):
        generator = _make_generator("not json at all")

        with pytest.raises(TopicGenerationError, match="not valid JSON"):
            await generator.generate_topics(count=1, exclude_titles=[])

    async def test_raises_when_response_is_not_a_string_array(self):
        generator = _make_generator('[{"title": "Battle of Plassey"}]')

        with pytest.raises(TopicGenerationError, match="not a JSON array"):
            await generator.generate_topics(count=1, exclude_titles=[])

    async def test_raises_when_response_contains_empty_strings(self):
        generator = _make_generator('["Battle of Plassey", ""]')

        with pytest.raises(TopicGenerationError, match="not a JSON array"):
            await generator.generate_topics(count=2, exclude_titles=[])
