# Content pipeline

Writes and publishes the daily article: an LLM proposes a topic, the pipeline scrapes sources on it, an LLM writes the
article from that material, automated checks accept or reject it, and it goes to Supabase.

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
| `LOG_LEVEL` | default `INFO` |

## Run

```bash
python scrapper/scrapper_main.py --count 1     # from the repo root
```

Each run calls the LLM at least twice per article (topic, then writing), so on a paid provider it costs money. It exits
0 only if every requested article was published, so a scheduled run that published nothing shows as failed. Logs are
JSON lines on stdout.

[`daily-pipeline.yml`](../.github/workflows/daily-pipeline.yml) runs the same command on demand in GitHub Actions
(`workflow_dispatch`) with the secrets `ANTHROPIC_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY`. Its daily schedule is commented out until the output quality is trusted.

## How a run works

1. **Topics** (`topic_generator.py`): asks the LLM for `--count` topics that match Wikipedia titles, excluding the 200
   most recent published titles.
2. **Scrape** (`web_scraper.py`, `sources/`): for each topic, one page from each of Wikipedia, archive.org and New World
   Encyclopedia, as Markdown through Crawl4AI and paced by a rate limiter (0.5 requests a second). A source that fails
   is logged and skipped; a topic with no content at all is skipped.
3. **Write** (`article_generator.py`): the LLM produces the title, summary, sections and tags from up to 15,000
   characters of source text. Citations and reading time come from the sources, not the LLM.
4. **Check** (`content_validator.py`): a title and summary, 1,300 to 2,200 words, at least 3 sections and 1 citation. It
   cannot check facts, and there is no human review yet. Up to 3 attempts per topic: a failed generation waits 5 s, then
   10 s; a failed check retries at once. Every attempt logs its word, section and citation counts.
5. **Publish** (`backend/services/article_service.py`): the content JSON goes to the `articles` Storage bucket and the
   metadata to the `articles` table, keyed by id, so publishing again overwrites.

One topic failing never stops the rest of the batch.

## Adding a source

Subclass `ContentSource` in `scrapper/sources/`, implement `search_topic`, register it in `sources/__init__.py`, and add
its `name` to `SOURCES` in `scheduler.py`; the scheduler only uses the sources listed there.

`WebScraper` has a `check_robots_txt` method, but the `respect_robots` argument is accepted and not applied: nothing
checks robots.txt before a page is fetched yet (see the [roadmap](../docs/roadmap.md)).

## Tests

```bash
cd scrapper && pytest -m "not integration"     # what CI runs; an 85% coverage gate is built in
```

The unit tests use stub LLM providers and sources, so they need no network or keys. `pytest -m integration` scrapes
real sites, so it needs network access and can fail when a site changes; CI skips it.
