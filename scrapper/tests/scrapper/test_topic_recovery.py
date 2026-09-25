"""
Unit tests for topic_recovery.recover_topic.

An article's title is an LLM-written headline, not the real Wikipedia title
image_sourcing.py (and a re-scrape) need -- recover the real one from the article's own
Wikipedia citation.
"""

from datetime import date, datetime, timezone

from common.models import Article, Citation
from scrapper.topic_recovery import recover_topic


def make_article(title="Mohenjo-daro", citations=()):
    return Article(
        id="art_20260101_001", title=title, summary="A summary.", content="...",
        citations=list(citations),
        publication_date=date(2026, 1, 1), reading_time_minutes=10,
    )


def wikipedia_citation(url="https://en.wikipedia.org/wiki/Mohenjo-daro"):
    return Citation(
        text="Mohenjo-daro", source_url=url, source_name="wikipedia",
        accessed_date=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )


def test_recovers_the_real_title_from_the_wikipedia_citation():
    article = make_article(
        title="Haldighati, 1576: The Battle Nobody Can Agree On",
        citations=[wikipedia_citation("https://en.wikipedia.org/wiki/Battle_of_Haldighati")],
    )

    assert recover_topic(article) == "Battle of Haldighati"


def test_url_decodes_the_title():
    article = make_article(citations=[
        wikipedia_citation("https://en.wikipedia.org/wiki/Rani_ki_Vav%20Stepwell"),
    ])

    assert recover_topic(article) == "Rani ki Vav Stepwell"


def test_falls_back_to_the_articles_own_title_with_no_wikipedia_citation():
    article = make_article(title="A Title With No Wikipedia Source", citations=[
        Citation(text="x", source_url="https://archive.org/details/x", source_name="archive_org",
                 accessed_date=datetime(2026, 1, 1, tzinfo=timezone.utc)),
    ])

    assert recover_topic(article) == "A Title With No Wikipedia Source"
