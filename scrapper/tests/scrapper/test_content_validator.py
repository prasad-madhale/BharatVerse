"""
Unit tests for ContentValidator.
"""

from datetime import date, datetime, timezone

from common.models import Article, Citation, Section
from scrapper.content_validator import ContentValidator


def _make_article(**overrides):
    defaults = dict(
        id="art_20260705_001",
        title="From Conquest to Compassion",
        summary="A summary of the article.",
        content=" ".join(["word"] * 1800),
        sections=[
            Section(heading="One", content="...", order=1),
            Section(heading="Two", content="...", order=2),
            Section(heading="Three", content="...", order=3),
        ],
        citations=[
            Citation(
                text="Ashoka",
                source_url="https://en.wikipedia.org/wiki/Ashoka",
                source_name="wikipedia",
                accessed_date=datetime(2026, 7, 5, tzinfo=timezone.utc),
            )
        ],
        publication_date=date(2026, 7, 5),
        reading_time_minutes=13,
    )
    defaults.update(overrides)
    return Article(**defaults)


class TestValidate:
    def test_valid_article_passes(self):
        validator = ContentValidator()

        valid, issues = validator.validate(_make_article())

        assert valid is True
        assert issues == []

    def test_empty_title_fails(self):
        validator = ContentValidator()

        valid, issues = validator.validate(_make_article(title="  "))

        assert valid is False
        assert any("title is empty" in issue for issue in issues)

    def test_empty_summary_fails(self):
        validator = ContentValidator()

        valid, issues = validator.validate(_make_article(summary=""))

        assert valid is False
        assert any("summary is empty" in issue for issue in issues)

    def test_too_short_word_count_fails(self):
        validator = ContentValidator()
        article = _make_article(content=" ".join(["word"] * 100))

        valid, issues = validator.validate(article)

        assert valid is False
        assert any("word count" in issue for issue in issues)

    def test_too_long_word_count_fails(self):
        validator = ContentValidator()
        article = _make_article(content=" ".join(["word"] * 5000))

        valid, issues = validator.validate(article)

        assert valid is False
        assert any("word count" in issue for issue in issues)

    def test_word_count_within_tolerance_passes(self):
        validator = ContentValidator()
        # 2150 words: over the 2000 target but within the 200-word tolerance.
        article = _make_article(content=" ".join(["word"] * 2150))

        valid, issues = validator.validate(article)

        assert valid is True
        assert issues == []

    def test_too_few_sections_fails(self):
        validator = ContentValidator()
        article = _make_article(sections=[Section(heading="One", content="...", order=1)])

        valid, issues = validator.validate(article)

        assert valid is False
        assert any("section" in issue for issue in issues)

    def test_no_citations_fails(self):
        validator = ContentValidator()
        article = _make_article(citations=[])

        valid, issues = validator.validate(article)

        assert valid is False
        assert any("citation" in issue for issue in issues)

    def test_multiple_failures_all_reported(self):
        validator = ContentValidator()
        article = _make_article(title="", sections=[], citations=[])

        valid, issues = validator.validate(article)

        assert valid is False
        assert len(issues) >= 3
