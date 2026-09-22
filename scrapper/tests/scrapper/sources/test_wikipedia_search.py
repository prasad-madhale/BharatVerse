"""
Unit tests for WikipediaSource.search_topic.

The fake `wikipedia` library honours the real return contract: search() returns a list of titles, but a
(titles, suggestion) tuple with suggestion=True. A fake that always returned a list would hide the bug
these tests exist to prevent.
"""

from unittest.mock import MagicMock, patch

import wikipedia

from scrapper.sources.wikipedia import WikipediaSource

URLS = {
    "Maurya Empire": "https://en.wikipedia.org/wiki/Maurya_Empire",
    "Mauryan Empire": "https://en.wikipedia.org/wiki/Maurya_Empire",  # redirect to the same page
    "Kalinga War": "https://en.wikipedia.org/wiki/Kalinga_War",
    "Chandragupta Maurya": "https://en.wikipedia.org/wiki/Chandragupta_Maurya",
}


def fake_wikipedia(hits, did_you_mean=None, suggested_hits=None):
    """Fake search/page functions and the patches that install them: (search_mock, page_mock, patches).

    `hits` answer the user's query, `did_you_mean` rides along as the suggestion, and `suggested_hits`
    answer a search for that suggestion.
    """
    def search(query, results=10, suggestion=False):
        titles = hits if query == "the query" else (suggested_hits or [])
        return (titles, did_you_mean) if suggestion else titles

    def page(title, auto_suggest=False):
        if title not in URLS:
            raise wikipedia.exceptions.PageError(str(title))
        result = MagicMock()
        result.title = title
        result.url = URLS[title]
        result.summary = f"About {title}."
        result.pageid = len(title)
        return result

    search_mock = MagicMock(side_effect=search)
    page_mock = MagicMock(side_effect=page)
    patches = (
        patch("scrapper.sources.wikipedia.wikipedia.search", search_mock),
        patch("scrapper.sources.wikipedia.wikipedia.page", page_mock),
    )
    return search_mock, page_mock, patches


def run_search(hits, did_you_mean=None, suggested_hits=None, **kwargs):
    search_mock, _, (search_patch, page_patch) = fake_wikipedia(hits, did_you_mean, suggested_hits)
    with search_patch, page_patch:
        results = WikipediaSource().search_topic("the query", **kwargs)
    return results, search_mock


class TestSearchTopic:
    def test_returns_every_search_hit_in_ranked_order(self):
        results, _ = run_search(["Maurya Empire", "Kalinga War", "Chandragupta Maurya"], max_results=3)

        assert [r["title"] for r in results] == ["Maurya Empire", "Kalinga War", "Chandragupta Maurya"]

    def test_default_call_requests_the_suggestion_tuple_and_unpacks_it(self):
        results, search_mock = run_search(["Kalinga War"], did_you_mean="kalinga war", max_results=3)

        search_mock.assert_called_once_with("the query", results=3, suggestion=True)
        assert [r["title"] for r in results] == ["Kalinga War"]

    def test_retries_with_the_suggestion_when_nothing_matches(self):
        results, search_mock = run_search(
            [], did_you_mean="maurya empire", suggested_hits=["Maurya Empire"], max_results=3
        )

        assert [r["title"] for r in results] == ["Maurya Empire"]
        assert search_mock.call_args_list[1].args == ("maurya empire",)
        assert search_mock.call_args_list[1].kwargs == {"results": 3}

    def test_returns_empty_when_neither_the_query_nor_the_suggestion_match(self):
        results, _ = run_search([], did_you_mean="nothing", suggested_hits=[])

        assert results == []

    def test_returns_empty_when_nothing_matches_and_there_is_no_suggestion(self):
        results, search_mock = run_search([], did_you_mean=None)

        assert results == []
        assert search_mock.call_count == 1

    def test_auto_suggest_off_never_asks_for_a_suggestion(self):
        results, search_mock = run_search(["Kalinga War"], auto_suggest=False, max_results=2)

        search_mock.assert_called_once_with("the query", results=2)
        assert [r["title"] for r in results] == ["Kalinga War"]

    def test_hits_resolving_to_the_same_url_are_collapsed(self):
        results, _ = run_search(["Maurya Empire", "Mauryan Empire", "Kalinga War"], max_results=3)

        assert [r["title"] for r in results] == ["Maurya Empire", "Kalinga War"]

    def test_unresolvable_titles_are_skipped(self):
        results, _ = run_search(["No Such Page", "Kalinga War"], max_results=2)

        assert [r["title"] for r in results] == ["Kalinga War"]
