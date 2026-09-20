---
id: TASK-003
title: Fix Wikipedia search: unpack the suggestion tuple and drop duplicate pages
depends_on: 
requires: py:crawl4ai, py:wikipedia
allowed: scrapper/scrapper/sources/wikipedia.py, scrapper/tests/scrapper/sources/test_wikipedia_search.py
verify: cd "$BV_ROOT/scrapper" && python -m pytest tests/scrapper/sources/test_wikipedia_search.py -q --no-cov -p no:cacheprovider
verify: cd "$BV_ROOT/scrapper" && python -m pytest -m "not integration" -q -p no:cacheprovider
verify: cd "$BV_ROOT" && python -m autopep8 --recursive --aggressive --aggressive --max-line-length=127 --exit-code --diff backend/ scrapper/ common/
verify: cd "$BV_ROOT" && python -m flake8 . --count --select=E9,F63,F7,F82 --exclude=.venv,.agent,.git,__pycache__,bharatverse_app,scripts
verify: cd "$BV_ROOT" && grep -q 'def _search_titles' scrapper/scrapper/sources/wikipedia.py
commit: fix: unpack wikipedia.search's suggestion tuple and drop duplicate pages
---

# TASK-003: Fix Wikipedia search: unpack the suggestion tuple and drop duplicate pages

## Why

`WikipediaSource.search_topic` calls `wikipedia.search(topic, results=N, suggestion=True)` by default. With
`suggestion=True` that library function returns a tuple, `(titles, suggestion)`, not a list. The code then loops over
the tuple as if it were the list of titles. The first "title" is the whole list and the second is the suggestion
string, so the wrong pages are scraped.

This was confirmed against the live Wikipedia API. Asking for three results for "Mauryan Empire" returned two pages,
in the wrong order, and dropped "Kalinga War". With `auto_suggest=False` all three came back correctly. The side
effect is the "same URL returned twice" symptom listed in the roadmap.

The fix has two parts: unpack the tuple (and retry with Wikipedia's suggestion when nothing matched), and skip a page
whose URL was already collected, since redirects can make two titles resolve to one page.

## Read first, and nothing else

- `scrapper/scrapper/sources/wikipedia.py`, only the `search_topic` and `_get_page_info` methods

## Steps

### Step 1. Route the search through a helper

<!-- step: replace scrapper/scrapper/sources/wikipedia.py -->
Replace this exact text:

```python
            search_results = wikipedia.search(topic, results=max_results, suggestion=auto_suggest)
```

with this exact text:

```python
            search_results = self._search_titles(topic, max_results, auto_suggest)
```

### Step 2. Skip duplicate URLs

<!-- step: replace scrapper/scrapper/sources/wikipedia.py -->
Replace this exact text:

```python
            results = []
            for title in search_results:
                page_info = self._get_page_info(title)
                if page_info:
                    results.append(page_info)
```

with this exact text:

```python
            results = []
            seen_urls = set()
            for title in search_results:
                page_info = self._get_page_info(title)
                if not page_info:
                    continue
                # Two search hits can resolve to the same article (redirects,
                # near-duplicate titles). Scraping it twice wastes a slot of the
                # per-source character budget for no new content.
                if page_info['url'] in seen_urls:
                    logger.debug(f"Skipping duplicate Wikipedia URL: {page_info['url']}")
                    continue
                seen_urls.add(page_info['url'])
                results.append(page_info)
```

### Step 3. Add the helper method

This inserts `_search_titles` directly above `_get_page_info`, keeping the `_get_page_info` line as it was.

<!-- step: replace scrapper/scrapper/sources/wikipedia.py -->
Replace this exact text:

```python
    def _get_page_info(self, title: str) -> Optional[Dict[str, str]]:
```

with this exact text:

```python
    def _search_titles(self, topic: str, max_results: int, auto_suggest: bool) -> List[str]:
        """
        Titles of the pages matching `topic`, best match first.

        wikipedia.search() returns a plain list of titles normally, but a
        (titles, suggestion) tuple when called with suggestion=True. The tuple
        must be unpacked: iterating it as if it were the title list yields the
        whole list as its first "title" and the suggestion string as its
        second, which resolves to the wrong pages.
        """
        if not auto_suggest:
            return wikipedia.search(topic, results=max_results)

        titles, suggestion = wikipedia.search(topic, results=max_results, suggestion=True)
        if not titles and suggestion:
            logger.info(f"No results for '{topic}'; retrying with Wikipedia's suggestion '{suggestion}'")
            titles = wikipedia.search(suggestion, results=max_results)
        return titles

    def _get_page_info(self, title: str) -> Optional[Dict[str, str]]:
```

### Step 4. Add the tests

Create `scrapper/tests/scrapper/sources/test_wikipedia_search.py` with exactly this content. The fake in it follows
the real library's contract: `search()` returns a list, except with `suggestion=True` it returns a tuple.

<!-- step: create scrapper/tests/scrapper/sources/test_wikipedia_search.py -->
```python
"""
Unit tests for WikipediaSource.search_topic.

These run against a fake of the `wikipedia` library that honours its real
return contract: search() returns a plain list of titles, except with
suggestion=True, when it returns a (titles, suggestion) tuple. A fake that
always returned a list would hide the bug these tests exist to prevent --
iterating that tuple as if it were the title list silently returned the
wrong pages. No network calls are made.
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
    """Build fake search/page functions and the patches that install them.

    hits:           titles returned for the user's own query.
    did_you_mean:   the suggestion string returned alongside them, if any.
    suggested_hits: titles returned when the suggestion is searched instead.
    Returns (search_mock, page_mock, patches); enter both patches to apply them.
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
```

## Verify

Run every `verify:` command from the front matter, from the repository root, and make each one exit 0.
If the formatting check prints a diff, run `python -m autopep8 --in-place --aggressive --aggressive
--max-line-length=127 <each file you changed>` and run the check again. Do not edit any file that is not listed
under `allowed`.

## Note on the full scrapper suite

A few existing scrapper tests call the live Wikipedia API. They need network access, and the second `verify:`
command runs them. If it fails only with connection errors, report `BLOCKED: no network` instead of changing tests.

## Definition of done

- Every step above was applied exactly as written.
- Every `verify:` command exits 0.
- Only files listed under `allowed` changed.
- You did not run git commit, checkout, reset, or push. The runner commits.

## Out of scope

Do not change the other two sources, the crawler configuration, or the character budget. Do not remove the citation
deduplication in `ArticleGenerator`.
