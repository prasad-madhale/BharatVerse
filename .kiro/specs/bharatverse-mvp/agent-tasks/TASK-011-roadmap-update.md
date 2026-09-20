---
id: TASK-011
title: Bring the roadmap up to date with search, likes, and the fixes
depends_on: TASK-010
requires: 
allowed: .kiro/specs/bharatverse-mvp/roadmap.md
verify: cd "$BV_ROOT" && grep -q 'Status as of 2026-09-20' .kiro/specs/bharatverse-mvp/roadmap.md
verify: cd "$BV_ROOT" && grep -q 'GET /articles/search?q=' .kiro/specs/bharatverse-mvp/roadmap.md
verify: cd "$BV_ROOT" && grep -q 'get_article_like_count' .kiro/specs/bharatverse-mvp/roadmap.md
verify: cd "$BV_ROOT" && grep -q 'Deviations from .design.md.' .kiro/specs/bharatverse-mvp/roadmap.md
verify: cd "$BV_ROOT" && ! grep -q 'Status as of 2026-07-09' .kiro/specs/bharatverse-mvp/roadmap.md
verify: cd "$BV_ROOT" && ! grep -q "Likes still doesn't exist" .kiro/specs/bharatverse-mvp/roadmap.md
verify: cd "$BV_ROOT" && ! grep -q 'GET /api/v1/search?q' .kiro/specs/bharatverse-mvp/roadmap.md
verify: cd "$BV_ROOT" && ! grep -q 'Unit-tested with a mocked' .kiro/specs/bharatverse-mvp/roadmap.md
commit: docs: bring the roadmap up to date with search, likes, and the fixes
---

# TASK-011: Bring the roadmap up to date with search, likes, and the fixes

## Why

In this repo the roadmap is the status source of truth, and feature work has been followed by a roadmap update each
time. It still says likes do not exist, gives the old search path, and describes tests that were replaced. It also
does not record where the implementation departs from `design.md`.

## Read first, and nothing else

- `.kiro/specs/bharatverse-mvp/roadmap.md`, only the status heading, the backend and scrapper bullets, Phase 2, and Phase 3

## Steps

### Step 1. Update the roadmap

This script makes six edits. Every replacement is anchored on text that must occur exactly once, and nothing is
written if any anchor fails. Run it exactly as written:

<!-- step: run -->
```bash
cd "$BV_ROOT" && python - <<'PY'
from pathlib import Path

p = Path(".kiro/specs/bharatverse-mvp/roadmap.md")
s = p.read_text()


def replace_once(text, old, new):
    assert text.count(old) == 1, f"text not unique or missing: {old!r}"
    return text.replace(old, new)


def replace_span(text, start_marker, end_marker, new):
    """Replace from start_marker through the end of end_marker. Both must occur exactly once."""
    assert text.count(start_marker) == 1, f"start marker not unique: {start_marker!r}"
    assert text.count(end_marker) == 1, f"end marker not unique: {end_marker!r}"
    start = text.index(start_marker)
    end = text.index(end_marker) + len(end_marker)
    assert start < end, "markers out of order"
    return text[:start] + new + text[end:]


# 1. Status date.
s = replace_once(s, "## Status as of 2026-07-09", "## Status as of 2026-09-20")

# 2. Backend bullet: search and likes now exist; sign-in no longer leaks a session.
s = replace_span(
    s,
    "`services/search_service.py` + `api/search.py` (`GET /search?q=...`) are new this pass",
    "Likes still doesn't exist.",
    "`services/search_service.py` + `api/search.py` (`GET /articles/search?q=...`, registered before the articles router so "
    "`/articles/{id}` cannot capture it) and `services/like_service.py` + `api/likes.py` (`POST`/`DELETE /articles/{id}/like`, "
    "`GET /users/me/likes`, matching `design.md`) are code-complete and unit-tested, but **not yet verified live** "
    "(see Phases 2 and 3 below). Sign-in and sign-up now run on a throwaway Supabase client, so a user's session can no "
    "longer leak into the shared anon client used for public reads.",
)

# 3. Scrapper bullet: the Wikipedia search fix.
s = replace_once(
    s,
    "Ground rules (85% coverage gate, blocking format/lint) enforced on every commit.",
    "Ground rules (85% coverage gate, blocking format/lint) enforced on every commit. "
    "`WikipediaSource.search_topic` now unpacks `wikipedia.search`'s `(titles, suggestion)` tuple and skips duplicate URLs; "
    "before, the default path scraped the wrong pages (confirmed against the live API), which was also the cause of "
    "the duplicate-URL symptom.",
)

# 4. Phase 2: the route, and why the tests changed shape.
s = replace_once(
    s,
    "(`GET /api/v1/search?q=...&limit=...`), wired into `main.py`.",
    "(`GET /api/v1/articles/search?q=...&limit=...`, the path `design.md` specifies), wired into `main.py`.",
)
s = replace_span(
    s,
    "Unit-tested with a mocked Supabase client",
    "full suite green, 98%+ coverage.",
    "Unit-tested by running the real service through a real postgrest query builder with a stub HTTP transport "
    "(`backend/tests/wire.py`), so the emitted query string is asserted rather than a mock's call list. The earlier "
    "mock-based tests hid two defects, both now fixed: a wrong `text_search` option name, and a call order that raised "
    "`AttributeError` on every request.",
)

# 5. Phase 3: the backend half is done.
s = replace_span(
    s,
    "- `backend/services/like_service.py` + `backend/api/likes.py`",
    "no schema changes needed.",
    "- `backend/services/like_service.py` + `backend/api/likes.py`: backend done, code-complete and unit-tested, **not yet "
    "verified live**. The endpoints match `design.md`, and `LikeService` has `like_article`, `unlike_article`, `is_liked`, "
    "`get_user_likes` (full articles) and `get_article_like_count`. It uses the service-role client, which bypasses RLS, "
    "so every per-user query filters on `user_id` explicitly and the tests assert that on the wire. Liking an unknown "
    "article returns 404. The schema and RLS needed no changes.",
)

# 6. Where the implementation deviates from design.md.
s = replace_once(
    s,
    "\n\n### Standing architectural decisions (confirmed with product owner)",
    "\n- Deviations from `design.md`: auth is `POST /auth/signup`, `/login`, `/logout`, while the design documents "
    "`/auth/register`, `/auth/refresh` and OAuth routes, which do not exist yet. Article responses do not include "
    "`is_liked`, which the design's examples show. Search results are ordered by date, not relevance.\n\n"
    "### Standing architectural decisions (confirmed with product owner)",
)

p.write_text(s)
print("roadmap.md updated")
PY
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

Do not change any other section of the roadmap and do not create any other documentation file.
