---
id: TASK-012
title: Bring the backend README's status and endpoint list up to date
depends_on: TASK-010
requires: 
allowed: backend/README.md
verify: cd "$BV_ROOT" && grep -q 'Implemented today' backend/README.md
verify: cd "$BV_ROOT" && grep -q 'auth/signup' backend/README.md
verify: cd "$BV_ROOT" && grep -q 'not built yet' backend/README.md
verify: cd "$BV_ROOT" && ! grep -q 'not yet implemented' backend/README.md
verify: cd "$BV_ROOT" && ! grep -q 'Phase 0 covers standing up' backend/README.md
commit: docs: bring the backend README's status and endpoint list up to date
---

# TASK-012: Bring the backend README's status and endpoint list up to date

## Why

The backend README opens by saying `backend/main.py` and everything under `api/` and `services/` are not implemented,
and its endpoint list does not distinguish what exists from what is only planned. The API endpoints it lists are the
design's target, and search and likes now match them.

## Read first, and nothing else

- `backend/README.md`, only the status note at the top, the "Project Structure" heading, and the "API Endpoints" section

## Steps

### Step 1. Update the README

This script replaces the status note, adds a sentence saying the directory tree is the target layout, and marks the
endpoints that are not built yet. Every replacement is anchored on text that must occur exactly once, and nothing is
written if any anchor fails. Run it exactly as written:

<!-- step: run -->
````bash
cd "$BV_ROOT" && python - <<'PY'
from pathlib import Path

p = Path("backend/README.md")
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


# 1. The status note at the top.
s = replace_span(
    s,
    "> **Status**: this document describes the target design.",
    "first article endpoints).",
    "> **Status**: the endpoint list below is the target design from\n"
    "> [design.md](../.kiro/specs/bharatverse-mvp/design.md). Implemented today: the article endpoints,\n"
    "> `GET /api/v1/articles/search`, the like endpoints, and email/password auth (`/auth/signup`, `/auth/login`,\n"
    "> `/auth/logout`). Search and likes are unit-tested but not yet verified against a live Supabase project.\n"
    "> Endpoints marked \"not built yet\" do not exist. See\n"
    "> [.kiro/specs/bharatverse-mvp/roadmap.md](../.kiro/specs/bharatverse-mvp/roadmap.md) for current status and build order.",
)

# 2. The directory tree is the target layout.
s = replace_once(
    s,
    "## Project Structure\n\n```\nbackend/",
    "## Project Structure\n\nThe layout below is the target design. `models/`, `utils/`, and `tests/` currently hold fewer files, and the LLM\n"
    "provider now lives in `common/`.\n\n```\nbackend/",
)

# 3. Mark what is not built.
for old, new in [
    ("- `GET /api/v1/articles/search/autocomplete?q=...` - Get autocomplete suggestions",
     "- `GET /api/v1/articles/search/autocomplete?q=...` - Get autocomplete suggestions (not built yet)"),
    ("- `GET /api/v1/articles/search/semantic?q=...` - Semantic similarity search",
     "- `GET /api/v1/articles/search/semantic?q=...` - Semantic similarity search (not built yet)"),
    ("- `POST /api/v1/auth/register` - Register with email/password",
     "- `POST /api/v1/auth/signup` - Register with email/password (the design calls this `/auth/register`)"),
    ("- `POST /api/v1/auth/oauth/google` - OAuth login with Google",
     "- `POST /api/v1/auth/oauth/google` - OAuth login with Google (not built yet)"),
    ("- `POST /api/v1/auth/oauth/facebook` - OAuth login with Facebook",
     "- `POST /api/v1/auth/oauth/facebook` - OAuth login with Facebook (not built yet)"),
    ("- `POST /api/v1/auth/refresh` - Refresh access token",
     "- `POST /api/v1/auth/refresh` - Refresh access token (not built yet)"),
]:
    s = replace_once(s, old, new)

p.write_text(s)
print("backend/README.md updated")
PY
````

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

Do not change any other section of the README and do not create any other documentation file.
