"""
Unit tests for shared Article/Section/Citation models.
"""

import json
from datetime import date, datetime, timezone

import pytest
from pydantic import ValidationError

from common.models import Article, Citation, Section


def _citation_kwargs(**overrides):
    kwargs = dict(
        text="Some citation text",
        source_url="https://en.wikipedia.org/wiki/Ashoka",
        source_name="Wikipedia",
        accessed_date=datetime(2026, 7, 5, tzinfo=timezone.utc),
    )
    kwargs.update(overrides)
    return kwargs


def _section_kwargs(**overrides):
    kwargs = dict(heading="Early Life", content="Some **markdown** content.", order=1)
    kwargs.update(overrides)
    return kwargs


def _article_kwargs(**overrides):
    kwargs = dict(
        id="art_20260705_001",
        title="From Conquest to Compassion",
        summary="A short summary of the article.",
        content="Full article body in Markdown.",
        publication_date=date(2026, 7, 5),
        reading_time_minutes=13,
    )
    kwargs.update(overrides)
    return kwargs


class TestCitation:
    def test_valid_citation(self):
        citation = Citation(**_citation_kwargs())
        assert citation.source_name == "Wikipedia"

    @pytest.mark.parametrize("missing_field", ["text", "source_url", "source_name", "accessed_date"])
    def test_missing_required_field_raises(self, missing_field):
        kwargs = _citation_kwargs()
        del kwargs[missing_field]
        with pytest.raises(ValidationError):
            Citation(**kwargs)

    def test_json_round_trip(self):
        citation = Citation(**_citation_kwargs())
        restored = Citation.model_validate_json(citation.model_dump_json())
        assert restored == citation


class TestSection:
    def test_valid_section(self):
        section = Section(**_section_kwargs())
        assert section.order == 1

    @pytest.mark.parametrize("missing_field", ["heading", "content", "order"])
    def test_missing_required_field_raises(self, missing_field):
        kwargs = _section_kwargs()
        del kwargs[missing_field]
        with pytest.raises(ValidationError):
            Section(**kwargs)

    def test_json_round_trip(self):
        section = Section(**_section_kwargs())
        restored = Section.model_validate_json(section.model_dump_json())
        assert restored == section


class TestArticle:
    def test_valid_article_minimal_fields(self):
        article = Article(**_article_kwargs())
        assert article.author == "BharatVerse AI"
        assert article.sections == []
        assert article.citations == []
        assert article.tags == []
        assert article.image_url is None
        assert isinstance(article.created_at, datetime)
        assert isinstance(article.updated_at, datetime)

    @pytest.mark.parametrize(
        "missing_field",
        ["id", "title", "summary", "content", "publication_date", "reading_time_minutes"],
    )
    def test_missing_required_field_raises(self, missing_field):
        kwargs = _article_kwargs()
        del kwargs[missing_field]
        with pytest.raises(ValidationError):
            Article(**kwargs)

    def test_article_with_sections_and_citations(self):
        article = Article(
            **_article_kwargs(
                sections=[Section(**_section_kwargs())],
                citations=[Citation(**_citation_kwargs())],
                tags=["ashoka-the-great", "mauryan-empire"],
                image_url="https://example.com/image.jpg",
            )
        )
        assert len(article.sections) == 1
        assert len(article.citations) == 1
        assert article.tags == ["ashoka-the-great", "mauryan-empire"]
        assert article.image_url == "https://example.com/image.jpg"

    def test_json_round_trip(self):
        article = Article(
            **_article_kwargs(
                sections=[Section(**_section_kwargs())],
                citations=[Citation(**_citation_kwargs())],
            )
        )
        restored = Article.model_validate_json(article.model_dump_json())
        assert restored == article

    def test_dict_round_trip_via_json_module(self):
        article = Article(**_article_kwargs())
        payload = json.loads(article.model_dump_json())
        assert payload["id"] == "art_20260705_001"
        assert payload["reading_time_minutes"] == 13
