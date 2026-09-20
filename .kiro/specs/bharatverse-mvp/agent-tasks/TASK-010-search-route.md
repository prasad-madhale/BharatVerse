---
id: TASK-010
title: Serve search at /articles/search, the path the design doc specifies
depends_on: TASK-005
requires: 
allowed: backend/api/search.py, backend/main.py, backend/tests/test_api/test_search.py
verify: cd "$BV_ROOT/backend" && python -m pytest tests/test_api/test_search.py -q --no-cov -p no:cacheprovider
verify: cd "$BV_ROOT/backend" && python -m pytest -m "not integration" -q -p no:cacheprovider
verify: cd "$BV_ROOT" && python -m autopep8 --recursive --aggressive --aggressive --max-line-length=127 --exit-code --diff backend/ scrapper/ common/
verify: cd "$BV_ROOT" && python -m flake8 . --count --select=E9,F63,F7,F82 --exclude=.venv,.agent,.git,__pycache__,bharatverse_app,scripts
verify: cd "$BV_ROOT" && grep -q 'prefix="/articles/search"' backend/api/search.py
verify: cd "$BV_ROOT" && ! grep -q 'prefix="/search"' backend/api/search.py
commit: fix: serve search at /articles/search as design.md specifies
---

# TASK-010: Serve search at /articles/search, the path the design doc specifies

## Why

`design.md` section 2.5 puts search at `GET /api/v1/articles/search`, and the backend README documents it there. The
search router was mounted at `/api/v1/search`.

Moving it has one trap. The articles router already has `GET /articles/{article_id}`, so if it is registered first,
a request for `/articles/search` is answered by that route with `search` as the article id. FastAPI matches routes in
registration order, so the search router must be registered before the articles router. A test asserts this: it fails
if the order is swapped.

## Read first, and nothing else

- `backend/api/search.py`
- `backend/main.py`

## Steps

### Step 1. Mount the router at the design path

<!-- step: replace backend/api/search.py -->
Replace this exact text:

```python
Autocomplete and semantic search are deferred -- see roadmap.md.
"""
```

with this exact text:

```python
Autocomplete and semantic search are deferred -- see roadmap.md.

Mounted at /articles/search, per design.md. main.py must register this router
before the articles router, whose /articles/{article_id} route would otherwise
capture the request and treat "search" as an article id.
"""
```

<!-- step: replace backend/api/search.py -->
Replace this exact text:

```python
router = APIRouter(prefix="/search", tags=["search"])
```

with this exact text:

```python
router = APIRouter(prefix="/articles/search", tags=["search"])
```

### Step 2. Register the search router before the articles router

One edit to `backend/main.py`. It replaces the whole block of four `include_router` lines: the search line moves to
the top, above the articles line, and the other three keep their order. Nothing is removed, so the result still has
all four routers.

<!-- step: replace backend/main.py -->
Replace this exact text:

```python
app.include_router(articles_router, prefix=settings.api_prefix)
app.include_router(auth_router, prefix=settings.api_prefix)
app.include_router(likes_router, prefix=settings.api_prefix)
app.include_router(search_router, prefix=settings.api_prefix)
```

with this exact text:

```python
# Registered before articles_router: /articles/search would otherwise be captured
# by its /articles/{article_id} route.
app.include_router(search_router, prefix=settings.api_prefix)
app.include_router(articles_router, prefix=settings.api_prefix)
app.include_router(auth_router, prefix=settings.api_prefix)
app.include_router(likes_router, prefix=settings.api_prefix)
```

### Step 3. Replace the search API tests

Every existing test uses the old path, and two routing tests are new. Read the file, then replace its entire contents
with exactly this:

<!-- step: create backend/tests/test_api/test_search.py -->
```python
"""
Unit tests for the search API router.

Uses FastAPI's TestClient with SearchService mocked out -- no live
Supabase or network calls.
"""

from datetime import date, datetime, timezone
from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

from backend.main import app
from common.models import Article, Section, Citation


def make_article():
    return Article(
        id="art_20260703_001",
        title="The Mauryan Empire",
        summary="A summary.",
        content="## Origins\n\nSome content.",
        sections=[Section(heading="Origins", content="Some content.", order=1)],
        citations=[
            Citation(
                text="Maurya Empire",
                source_url="https://en.wikipedia.org/wiki/Maurya_Empire",
                source_name="wikipedia",
                accessed_date=datetime(2026, 7, 3, tzinfo=timezone.utc),
            )
        ],
        publication_date=date(2026, 7, 3),
        reading_time_minutes=13,
        tags=["mauryan-empire"],
    )


@pytest.fixture
def client():
    return TestClient(app)


class TestSearchArticles:
    def test_returns_matches_from_service(self, client):
        with patch("backend.api.search.SearchService") as mock_service_class:
            mock_service_class.return_value.search_articles = AsyncMock(return_value=[make_article()])

            response = client.get("/api/v1/articles/search?q=Ashoka")

        assert response.status_code == 200
        body = response.json()
        assert len(body) == 1
        assert body[0]["id"] == "art_20260703_001"

    def test_returns_empty_list_when_no_matches(self, client):
        with patch("backend.api.search.SearchService") as mock_service_class:
            mock_service_class.return_value.search_articles = AsyncMock(return_value=[])

            response = client.get("/api/v1/articles/search?q=nonexistent")

        assert response.status_code == 200
        assert response.json() == []

    def test_passes_query_and_default_limit_through(self, client):
        with patch("backend.api.search.SearchService") as mock_service_class:
            mock_service_class.return_value.search_articles = AsyncMock(return_value=[])

            client.get("/api/v1/articles/search?q=Ashoka")

        mock_service_class.return_value.search_articles.assert_called_once_with("Ashoka", limit=20)

    def test_passes_limit_query_param_through(self, client):
        with patch("backend.api.search.SearchService") as mock_service_class:
            mock_service_class.return_value.search_articles = AsyncMock(return_value=[])

            client.get("/api/v1/articles/search?q=Ashoka&limit=3")

        mock_service_class.return_value.search_articles.assert_called_once_with("Ashoka", limit=3)

    def test_rejects_missing_query(self, client):
        response = client.get("/api/v1/articles/search")

        assert response.status_code == 422

    def test_rejects_empty_query(self, client):
        response = client.get("/api/v1/articles/search?q=")

        assert response.status_code == 422

    def test_rejects_limit_above_max(self, client):
        response = client.get("/api/v1/articles/search?q=Ashoka&limit=51")

        assert response.status_code == 422


class TestRouting:
    def test_search_is_served_at_the_design_doc_path(self, client):
        paths = client.get("/openapi.json").json()["paths"]

        assert "/api/v1/articles/search" in paths
        assert "/api/v1/search" not in paths

    def test_search_is_not_captured_by_the_article_by_id_route(self, client):
        # If articles_router were registered first, its /articles/{article_id} route
        # would answer this request and treat "search" as an article id.
        with patch("backend.api.search.SearchService") as mock_search_class, \
                patch("backend.api.articles.ArticleService") as mock_article_class:
            mock_search_class.return_value.search_articles = AsyncMock(return_value=[])

            response = client.get("/api/v1/articles/search?q=Ashoka")

        assert response.status_code == 200
        mock_article_class.assert_not_called()
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

Do not change the search service, the schema, or the article endpoints. Do not add autocomplete.
