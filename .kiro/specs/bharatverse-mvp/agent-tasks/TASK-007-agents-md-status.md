---
id: TASK-007
title: Bring AGENTS.md up to date with what exists
depends_on: TASK-001, TASK-005
requires: 
allowed: .kiro/AGENTS.md
verify: cd "$BV_ROOT" && ! grep -q 'does not exist yet' .kiro/AGENTS.md
verify: cd "$BV_ROOT" && ! grep -q 'not yet built' .kiro/AGENTS.md
verify: cd "$BV_ROOT" && ! grep -q 'starter template' .kiro/AGENTS.md
verify: cd "$BV_ROOT" && ! grep -q 'widget_test.dart' .kiro/AGENTS.md
verify: cd "$BV_ROOT" && ! grep -q 'empty placeholders' .kiro/AGENTS.md
verify: cd "$BV_ROOT" && grep -q 'new_world_encyclopedia.py' .kiro/AGENTS.md
verify: cd "$BV_ROOT" && grep -q 'backend/tests/wire.py' .kiro/AGENTS.md
verify: cd "$BV_ROOT" && grep -q 'Development mode with hot reload:' .kiro/AGENTS.md
commit: docs: bring AGENTS.md up to date with what exists
---

# TASK-007: Bring AGENTS.md up to date with what exists

## Why

`AGENTS.md` is the guide an AI agent reads before working in this repo, and it still claims several files do not
exist: `backend/main.py`, `scrapper/scrapper_main.py`, and every screen in the mobile app. An agent that believes it
will try to recreate them. It also lists the sources incompletely and describes the backend tests as empty
placeholders.

## Read first, and nothing else

- `.kiro/AGENTS.md`

## Steps

### Step 1. Rewrite the stale passages

This script rewrites seven passages. Every replacement is anchored on text that must occur exactly once, and nothing
is written if any anchor fails. Run it exactly as written:

<!-- step: run -->
````bash
cd "$BV_ROOT" && python - <<'PY'
from pathlib import Path

p = Path(".kiro/AGENTS.md")
s = p.read_text()


def replace_span(text, start_marker, end_marker, new):
    """Replace from start_marker through the end of end_marker. Both must occur exactly once."""
    assert text.count(start_marker) == 1, f"start marker not unique: {start_marker!r}"
    assert text.count(end_marker) == 1, f"end marker not unique: {end_marker!r}"
    start = text.index(start_marker)
    end = text.index(end_marker) + len(end_marker)
    assert start < end, "markers out of order"
    return text[:start] + new + text[end:]


def replace_once(text, old, new):
    assert text.count(old) == 1, f"text not unique: {old!r}"
    return text.replace(old, new)


# 1. Status blockquote at the top.
s = replace_span(
    s,
    "> **Current implementation status**",
    "before assuming any of the \"target\" instructions below already work.\n",
    """> **Current implementation status**: the scrape, generate, validate, store, serve, and display pipeline works
> end to end (the roadmap records what has been verified live). `scrapper/` has `scrapper_main.py`, the daily
> scheduler, topic generation, and content validation. `backend/` has `main.py` with articles, auth, search, and
> likes routers. `bharatverse_app/` has Home, Article Detail, and Sign-in screens. Search and likes are not yet
> verified against a live Supabase project, and the app has no search, likes, or offline-cache screens yet. See
> [.kiro/specs/bharatverse-mvp/roadmap.md](specs/bharatverse-mvp/roadmap.md) for the current build order.
""",
)

# 2. Flutter overview.
s = replace_once(
    s,
    "This is a standard Flutter application.",
    "A Flutter app using Provider for state, Supabase for auth, and the Vintage Broadsheet design system. "
    "Screens: Home, Article Detail, Sign-in.",
)

# 3. Flutter test directory description.
s = replace_once(
    s,
    "`test/widget_test.dart` is an example widget test.",
    "Grouped as `test/models/`, `test/services/`, `test/screens/`, and `test/state/`.",
)

# 4. How to run the scraper.
s = replace_span(
    s,
    "`scrapper/scrapper_main.py` does not exist yet",
    "(`scrapper/scrapper/web_scraper.py`).\n",
    """`scrapper/scrapper_main.py` runs the daily content pipeline: topic selection, multi-source scrape, LLM
generation, validation, and storage in Supabase. It makes real LLM calls and writes to the live database, so run
it deliberately, never from a test or an automated loop:
```bash
python scrapper/scrapper_main.py --count 1
```
""",
)

# 5. Scrapper code-organization bullets.
s = replace_span(
    s,
    "*   `scrapper_main.py`: Planned pipeline entry point",
    "see status note above).\n",
    "*   `scrapper_main.py`: Pipeline entry point, a thin `--count N` CLI over `scrapper/scheduler.py`.\n",
)
s = replace_once(
    s,
    "(`wikipedia.py`, `archive_org.py`)",
    "(`wikipedia.py`, `archive_org.py`, `new_world_encyclopedia.py`)",
)

# 6. How to run the backend.
s = replace_span(
    s,
    "`backend/main.py` does not exist yet",
    "development mode with hot reload will be:\n",
    "Development mode with hot reload:\n",
)

# 7. Backend testing approach.
s = replace_span(
    s,
    "`backend/tests/` has substantive coverage",
    "source directories.\n",
    """`backend/tests/` covers config, the Supabase client, the API routers (`test_api/`), the services
(`test_services/`), and property-based persistence tests in `test_database/` (Hypothesis, some marked
`@pytest.mark.integration` and requiring a live Supabase connection). Query-shape tests run the real service
through the real postgrest builder via `backend/tests/wire.py`, so a wrong operator or call order fails a test
instead of passing a mock.
""",
)

p.write_text(s)
print("AGENTS.md updated")
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

Do not change any other passage in `AGENTS.md`, do not edit the "target" instructions that are still accurate, and do
not create any other documentation file.
