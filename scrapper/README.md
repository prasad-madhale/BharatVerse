# Content pipeline

Writes and publishes the daily article: an LLM proposes a topic, the pipeline scrapes sources on it, an LLM writes the
article from that material, automated checks and an LLM editor accept or reject it, and it goes to Supabase.

## Setup

Python 3.12. From the repo root, in a virtualenv:

```bash
pip install -r backend/requirements.txt -r scrapper/requirements.txt   # publishing reuses the backend's article service
playwright install chromium                                             # Crawl4AI drives a headless browser
```

Put these in the `.env` at the repo root (template: [`.env.example`](../.env.example)):

| Variable | Meaning |
|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | the project to publish to (the service-role key writes) |
| `LLM_PROVIDER` | `gemini` (default; has a free tier), `anthropic`, `openai` or `groq` |
| `GEMINI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GROQ_API_KEY` | the key for the chosen provider |
| `LLM_MODEL` | optional; defaults per provider are listed in `.env.example` |
| `CRITIC_ENABLED` | default `true`; `false` skips the editorial critic pass, for a cheap local run |
| `LOG_LEVEL` | default `INFO` |

## Run

```bash
python scrapper/scrapper_main.py --count 1     # from the repo root
```

Each run calls the LLM at least three times per article (topic, writing, one editorial review), more if the critic
asks for a revision, so on a paid provider it costs money -- set `CRITIC_ENABLED=false` to hold it to two. It exits
0 only if every requested article was published, so a scheduled run that published nothing shows as failed. Logs are
JSON lines on stdout.

[`daily-pipeline.yml`](../.github/workflows/daily-pipeline.yml) runs the same command on demand in GitHub Actions
(`workflow_dispatch`) with the secrets `ANTHROPIC_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY`. Its daily schedule is commented out until the output quality is trusted.

## How a run works

1. **Topics** (`topic_generator.py`): asks the LLM for `--count` topics that match Wikipedia titles, excluding the 200
   most recent published titles.
2. **Scrape** (`web_scraper.py`, `sources/`): for each topic, one page from each of Wikipedia, archive.org, New World
   Encyclopedia and the Indian Culture Portal, as Markdown through Crawl4AI (or, for the Portal, a real browser
   session directly -- see `sources/indian_culture.py`) and paced by a rate limiter (0.5 requests a second). A source
   that fails is logged and skipped; a topic with no content at all is skipped.
3. **Write** (`article_generator.py`): the LLM produces the title, summary, sections and tags from up to 15,000
   characters of source text. Citations and reading time come from the sources, not the LLM.
4. **Check** (`content_validator.py`): a title and summary, 1,300 to 2,200 words, at least 3 sections and 1 citation --
   cheap and structural; it cannot check facts.
5. **Review** (`article_critic.py`, skipped if `CRITIC_ENABLED=false`): an LLM edits the way a history-encyclopedia
   editor would -- is every claim grounded in the scraped source text (not just differently worded, actually
   invented), do the citations support what's near them, is the framing neutral, is a debated claim hedged, does it
   have a real structure. `article_generator.py`'s `revise_article` addresses what it finds and it reviews again, up
   to `CRITIC_MAX_ROUNDS` (2) times in `scheduler.py`; a revision that fails the structural check ends the round
   early. There is still no human review.
6. **Publish** (`backend/services/article_service.py`): the content JSON goes to the `articles` Storage bucket and the
   metadata to the `articles` table, keyed by id, so publishing again overwrites.

Up to 3 attempts per topic: a failed generation waits 5 s, then 10 s; a failed structural check or a critic that never
approves retries with a fresh generation at once. Every attempt logs its word, section and citation counts, and (once
past the structural check) the critic's round count and verdict. One topic failing never stops the rest of the batch.

## Adding a source

Subclass `ContentSource` in `scrapper/sources/`, implement `search_topic`, register it in `sources/__init__.py`, and add
its `name` to `SOURCES` in `scheduler.py`; the scheduler only uses the sources listed there. If a site needs a real
browser for search too, not just for rendering a result page (`indian_culture.py`'s docstring has why), override
`extract` as well rather than relying on the base class's `search_topic`-then-Crawl4AI default.

`WebScraper` has a `check_robots_txt` method, but the `respect_robots` argument is accepted and not applied: nothing
checks robots.txt before a page is fetched yet (see the [roadmap](../docs/roadmap.md)).

## Tests

```bash
cd scrapper && pytest -m "not integration"     # what CI runs; an 85% coverage gate is built in
```

The unit tests use stub LLM providers and sources, so they need no network or keys. `pytest -m integration` scrapes
real sites, so it needs network access and can fail when a site changes; CI skips it. The Indian Culture Portal's
own live-network tests are marked `integration` too, for a different reason than most: confirmed in a real CI run
that the site's bot-detection can refuse the connection outright depending on which of GitHub Actions' rotating IPs
the job lands on (a re-run from a fresh IP passed). The filtering and markdown-conversion logic that matters for
correctness is covered separately, against a canned payload, so that stays in the default suite.
