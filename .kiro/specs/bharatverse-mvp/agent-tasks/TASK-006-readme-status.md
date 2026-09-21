---
id: TASK-006
title: Bring the README's project status up to date
depends_on: TASK-005
requires: 
allowed: README.md
verify: cd "$BV_ROOT" && ! grep -q 'starter template' README.md
verify: cd "$BV_ROOT" && ! grep -q 'once backend/main.py exists' README.md
verify: cd "$BV_ROOT" && ! grep -q 'are not yet built' README.md
verify: cd "$BV_ROOT" && grep -q 'scrapper_main.py --count' README.md
verify: cd "$BV_ROOT" && grep -q 'Sign-in screens' README.md
verify: cd "$BV_ROOT" && grep -q 'authoritative' README.md
commit: docs: bring the README's project status up to date
---

# TASK-006: Bring the README's project status up to date

## Why

The README's Project Status section still says the backend has no `main.py`, the scraper has no generation or
scheduler, and the mobile app is the default Flutter template. All three are now false. Anyone, human or agent, who
trusts it will plan work that is already done.

## Read first, and nothing else

- `README.md`, only the "Project Status" section near the top and the "Backend API" build step

## Steps

### Step 1. Rewrite the status text

This script replaces the stale text. It stops with a clear message if any anchor is missing or appears more than
once, and it writes nothing in that case. Run it exactly as written:

<!-- step: run -->
```bash
cd "$BV_ROOT" && python - <<'PY'
from pathlib import Path

p = Path("README.md")
s = p.read_text()


def replace_span(text, start_marker, end_marker, new):
    """Replace from start_marker through the end of end_marker. Both must occur exactly once."""
    assert text.count(start_marker) == 1, f"start marker not unique: {start_marker!r}"
    assert text.count(end_marker) == 1, f"end marker not unique: {end_marker!r}"
    start = text.index(start_marker)
    end = text.index(end_marker) + len(end_marker)
    assert start < end, "markers out of order"
    return text[:start] + new + text[end:]


STATUS = """This project is early-stage but works end to end: the core scrape, AI-generate, validate, store, serve, and
display pipeline has been run live. See **[.kiro/specs/bharatverse-mvp/roadmap.md](.kiro/specs/bharatverse-mvp/roadmap.md)**
for the authoritative, phase-by-phase status and the remaining build order. In short:
- `scrapper/`: scraping (Wikipedia, archive.org, New World Encyclopedia via Crawl4AI), LLM article generation,
  content validation, and the daily scheduler CLI (`python scrapper/scrapper_main.py --count N`) all work. The
  daily GitHub Actions trigger is deliberately disabled (manual runs only) until output quality is trusted.
- `backend/`: the FastAPI app (`backend/main.py`) serves articles and email/password auth via Supabase Auth.
  Full-text search and article likes are implemented and unit-tested but not yet verified against a live
  Supabase project. The mobile app currently reads articles directly from Supabase, not through this API.
- `bharatverse_app/`: Home, Article Detail, and Sign-in screens are built in the "Vintage Broadsheet" design
  system. Search, likes, and offline caching are not built yet.
"""
s = replace_span(s, "This project is early-stage", "no screens have been built yet.\n", STATUS)

old_start = "# Run API server (once backend/main.py exists"
assert s.count(old_start) == 1, "run-server comment not unique"
i = s.index(old_start)
j = s.index("\n", i)
s = s[:i] + "# Run API server" + s[j:]

p.write_text(s)
print("README.md updated")
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

Do not change any other section of the README, and do not create any other documentation file.
