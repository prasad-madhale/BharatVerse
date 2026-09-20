---
id: TASK-002
title: Make the daily article deterministic when two articles share a date
depends_on: TASK-001
requires: 
allowed: backend/services/article_service.py, backend/tests/test_services/test_article_service.py, backend/tests/test_services/test_daily_article.py
verify: cd "$BV_ROOT/backend" && python -m pytest tests/test_services/test_daily_article.py -q --no-cov -p no:cacheprovider
verify: cd "$BV_ROOT/backend" && python -m pytest -m "not integration" -q -p no:cacheprovider
verify: cd "$BV_ROOT" && python -m autopep8 --recursive --aggressive --aggressive --max-line-length=127 --exit-code --diff backend/ scrapper/ common/
verify: cd "$BV_ROOT" && python -m flake8 . --count --select=E9,F63,F7,F82 --exclude=.venv,.agent,.git,__pycache__,bharatverse_app,scripts
verify: cd "$BV_ROOT" && grep -q '.order("created_at", desc=True)' backend/services/article_service.py
verify: cd "$BV_ROOT" && ! grep -q 'class TestGetDailyArticle' backend/tests/test_services/test_article_service.py
commit: fix: break daily-article ties on created_at for a stable result
---

# TASK-002: Make the daily article deterministic when two articles share a date

## Why

`ArticleService.get_daily_article` sorts by `date` descending and takes one row. When two articles carry the same
date, which one wins is whatever order Postgres happens to return. A second sort key makes it deterministic: the
most recently created article wins.

This task uses the `WireClient` helper that TASK-001 created in `backend/tests/wire.py`, so the new test asserts the
real query string rather than a mock's call list.

## Read first, and nothing else

- `backend/services/article_service.py`, only the `get_daily_article` method
- `backend/tests/test_services/test_article_service.py`, only its last class, `TestGetDailyArticle`

## Steps

### Step 1. Add the second sort key

<!-- step: replace backend/services/article_service.py -->
Replace this exact text:

```python
        Phase 0: the most recently published article by date. Real
        daily-selection logic (one designated article per calendar day,
        topic uniqueness) is a Phase 4 (scheduler) concern.
        """
        client = get_supabase().get_client()
        response = (
            client.table("articles")
            .select("*")
            .order("date", desc=True)
            .limit(1)
            .execute()
        )
```

with this exact text:

```python
        The most recently published article by date, breaking ties on
        created_at so the result is stable when two articles share a date.
        Real daily-selection logic (one designated article per calendar day,
        topic uniqueness) is a Phase 4 (scheduler) concern.
        """
        client = get_supabase().get_client()
        response = (
            client.table("articles")
            .select("*")
            .order("date", desc=True)
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
```

### Step 2. Remove the old daily-article tests

`TestGetDailyArticle` is the last class in `test_article_service.py`. It uses a mock chain that the second sort key
breaks, and Step 3 replaces it. Delete it by running this command exactly:

<!-- step: run -->
```bash
cd "$BV_ROOT" && python -c "from pathlib import Path; p = Path('backend/tests/test_services/test_article_service.py'); s = p.read_text(); i = s.index('class TestGetDailyArticle:'); p.write_text(s[:i].rstrip() + chr(10))"
```

### Step 3. Add the new daily-article tests

Create `backend/tests/test_services/test_daily_article.py` with exactly this content:

<!-- step: create backend/tests/test_services/test_daily_article.py -->
```python
"""
Unit tests for ArticleService.get_daily_article.

The ordering test drives the real service through a real postgrest query
builder (see backend/tests/wire.py) and asserts on the HTTP request that
would be sent, so a wrong sort key or a wrong call order cannot pass unseen.
"""

import json
from unittest.mock import MagicMock, patch

import httpx
import pytest

from backend.services.article_service import ArticleService
from backend.tests.wire import WireClient


def make_row(article_id="art_20260703_001"):
    return {
        "id": article_id,
        "title": "The Mauryan Empire",
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


class TestGetDailyArticle:
    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_returns_none_when_no_articles(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[]))
        mock_get_supabase.return_value.get_client.return_value = wire

        assert await ArticleService().get_daily_article() is None

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_sorts_newest_date_first_then_newest_created_first(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[]))
        mock_get_supabase.return_value.get_client.return_value = wire

        await ArticleService().get_daily_article()

        (request,) = wire.requests
        assert request.url.path == "/rest/v1/articles"
        # Two sort keys reach PostgREST as one comma-joined order parameter.
        # created_at is the tie-break when two articles share a date.
        assert request.url.params["order"] == "date.desc,created_at.desc"
        assert request.url.params["limit"] == "1"

    @pytest.mark.asyncio
    @patch("backend.services.article_service.get_supabase")
    async def test_returns_the_first_row_as_a_full_article(self, mock_get_supabase):
        wire = WireClient(lambda request: httpx.Response(200, json=[make_row()]))
        wire.storage = MagicMock()
        wire.storage.from_.return_value.download.return_value = make_blob()
        mock_get_supabase.return_value.get_client.return_value = wire

        article = await ArticleService().get_daily_article()

        assert article.id == "art_20260703_001"
        assert article.sections[0].heading == "Origins"
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

Do not change `list_recent_articles` or `list_recent_titles`. Do not change how article dates are assigned. Do not
add a column or a `published` flag.
