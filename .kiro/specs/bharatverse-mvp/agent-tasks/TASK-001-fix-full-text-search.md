---
id: TASK-001
title: Fix full-text search (two defects) and pin them with wire-level tests
depends_on: 
requires: py:postgrest, py:httpx
allowed: backend/services/search_service.py, backend/tests/test_services/test_search_service.py, backend/tests/wire.py
verify: cd "$BV_ROOT/backend" && python -m pytest tests/test_services/test_search_service.py -q --no-cov -p no:cacheprovider
verify: cd "$BV_ROOT/backend" && python -m pytest -m "not integration" -q -p no:cacheprovider
verify: cd "$BV_ROOT" && python -m autopep8 --recursive --aggressive --aggressive --max-line-length=127 --exit-code --diff backend/ scrapper/ common/
verify: cd "$BV_ROOT" && python -m flake8 . --count --select=E9,F63,F7,F82 --exclude=.venv,.agent,.git,__pycache__,bharatverse_app,scripts
verify: cd "$BV_ROOT" && grep -q '"type": "web_search"' backend/services/search_service.py
verify: cd "$BV_ROOT" && ! grep -q '"type": "websearch"' backend/services/search_service.py
commit: fix: full-text search used a wrong query option and an invalid call order
---

# TASK-001: Fix full-text search (two defects) and pin them with wire-level tests

## Why

The search feature has two defects. Both are invisible to the existing tests, which only check a mocked client.

1. The service asks postgrest for a query type named `websearch`. postgrest-py only recognises `web_search`. Any
   other value silently falls back to PostgREST's strict `fts` operator, which rejects a multi-word query such as
   "Mauryan Empire".
2. The service calls `.text_search(...)` before `.order(...)` and `.limit(...)`. In postgrest-py, `text_search()`
   returns a builder that has only `execute()`, so every search raises `AttributeError`.

Both were confirmed by building the real query offline. The code change is small. The new tests are the point: they
run the real service through a real query builder and assert the HTTP request that would be sent to Supabase.

## Read first, and nothing else

- `backend/services/search_service.py`
- `backend/tests/test_services/test_search_service.py`

## Steps

### Step 1. Create the test helper

Create `backend/tests/wire.py` with exactly this content:

<!-- step: create backend/tests/wire.py -->
```python
"""
Test support: a real postgrest query builder wired to a stub HTTP transport.

Mocking `client.table(...).select(...)` proves a call happened, not what
would actually be sent to Supabase. A wrong operator name or option value
passes a mock-based test and still fails in production. This helper runs
the real service code against a real query builder and records the HTTP
request that would have gone out, so a test can assert on the real path and
query string.
"""

import httpx
from postgrest import SyncPostgrestClient

BASE_URL = "https://example.supabase.co/rest/v1"
_HEADERS = {"apikey": "test", "Accept": "application/json", "Content-Type": "application/json"}


class WireClient:
    """Just enough of the Supabase client surface for the services: table()."""

    def __init__(self, handler):
        self.requests: list[httpx.Request] = []

        def recording_handler(request: httpx.Request) -> httpx.Response:
            self.requests.append(request)
            return handler(request)

        self._postgrest = SyncPostgrestClient(BASE_URL, headers=_HEADERS)
        self._postgrest.session = httpx.Client(
            base_url=BASE_URL,
            headers=_HEADERS,
            transport=httpx.MockTransport(recording_handler),
        )

    def table(self, name: str):
        return self._postgrest.from_(name)
```

### Step 2. Fix the service

<!-- step: replace backend/services/search_service.py -->
Replace this exact text:

```python
        client = get_supabase().get_client()
        response = (
            client.table("articles")
            .select("*")
            .text_search("search_vector", query, options={"type": "websearch", "config": "english"})
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
```

with this exact text:

```python
        client = get_supabase().get_client()
        # text_search() must be the LAST builder call before execute(): it returns
        # a builder that only has execute(), so order()/limit() after it raise
        # AttributeError. The option type is "web_search" (postgrest-py's spelling),
        # which emits PostgREST's wfts operator; any other value falls back to the
        # strict fts operator and rejects multi-word queries.
        response = (
            client.table("articles")
            .select("*")
            .order("date", desc=True)
            .limit(limit)
            .text_search("search_vector", query, options={"type": "web_search", "config": "english"})
            .execute()
        )
```

### Step 3. Replace the search tests

Every existing test in this file asserts the wrong option value and the impossible call order, so they cannot
stay. Read the file, then replace its entire contents with exactly this:

<!-- step: create backend/tests/test_services/test_search_service.py -->
```python
"""
Unit tests for SearchService.

The query-shape tests drive the real service through a real postgrest query
builder (see backend/tests/wire.py) and assert on the HTTP request that would
be sent to Supabase. A mock-based test cannot catch a wrong operator name or
a wrong builder-call order, and both went unnoticed once already.
"""

import json
from unittest.mock import MagicMock, patch

import httpx
import pytest

from backend.services.search_service import SearchService
from backend.tests.wire import WireClient


def make_row(article_id="art_20260703_001", title="The Mauryan Empire"):
    return {
        "id": article_id,
        "title": title,
        "summary": "A summary.",
        "date": "2026-07-03",
        "reading_time_minutes": 13,
        "author": "BharatVerse AI",
        "tags": ["mauryan-empire"],
        "image_url": None,
        "content_file_path": f"articles/2026-07-03/{article_id}.json",
        "created_at": "2026-07-03T00:00:00Z",
        "updated_at": "2026-07-03T00:00:00Z",
    }


def make_blob():
    return json.dumps({
        "content": "## Origins\n\nSome content.",
        "sections": [{"heading": "Origins", "content": "Some content.", "order": 1}],
        "citations": [],
    }).encode("utf-8")


class TestSearchArticles:
    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_sends_websearch_query_ordered_by_date_with_limit(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[]))
        mock_get_supabase.return_value.get_client.return_value = wire

        results = await SearchService().search_articles("Mauryan Empire", limit=7)

        assert results == []
        (request,) = wire.requests
        assert request.url.path == "/rest/v1/articles"
        assert request.url.params["select"] == "*"
        # wfts is PostgREST's websearch_to_tsquery operator. The strict fts
        # operator would reject a two-word query like this one.
        assert request.url.params["search_vector"] == "wfts(english).Mauryan Empire"
        assert request.url.params["order"] == "date.desc"
        assert request.url.params["limit"] == "7"

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_default_limit_is_twenty(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[]))
        mock_get_supabase.return_value.get_client.return_value = wire

        await SearchService().search_articles("Ashoka")

        assert wire.requests[0].url.params["limit"] == "20"

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_reassembles_full_articles_from_matched_rows(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[make_row()]))
        wire.storage = MagicMock()
        wire.storage.from_.return_value.download.return_value = make_blob()
        mock_get_supabase.return_value.get_client.return_value = wire

        results = await SearchService().search_articles("Ashoka")

        assert len(results) == 1
        assert results[0].id == "art_20260703_001"
        assert results[0].title == "The Mauryan Empire"
        assert results[0].sections[0].heading == "Origins"

    @pytest.mark.asyncio
    @patch("backend.services.search_service.get_supabase")
    async def test_returns_empty_list_when_no_matches(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[]))
        mock_get_supabase.return_value.get_client.return_value = wire

        assert await SearchService().search_articles("no such topic") == []
```

## Verify

Run every `verify:` command from the front matter, from the repository root, and make each one exit 0.
If the formatting check prints a diff, run `python -m autopep8 --in-place --aggressive --aggressive
--max-line-length=127 <each file you changed>` and run the check again. Do not edit any file that is not listed
under `allowed`.

## Definition of done

- Every step above was applied exactly as written.
- Every `verify:` command exits 0.
- Only files listed under `allowed` changed.
- You did not run git commit, checkout, reset, or push. The runner commits.

## Out of scope

Do not touch `schema.sql`, `api/search.py`, or `main.py`. Do not try to reach a live Supabase project. The database
migration that adds the `search_vector` column is done by a person.
