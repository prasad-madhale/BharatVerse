# BharatVerse

One AI-written story from Indian history a day. A Python pipeline scrapes sources, has an LLM write the article,
validates it and publishes it to Supabase; a Flutter app (iOS, Android, web) reads it from there; a FastAPI service
serves the same data as a REST API.

**Status:** the pipeline, app and API work end to end. [docs/roadmap.md](docs/roadmap.md) lists what is built, where it
differs from the design, and what still needs a person (hosted-project setup, OAuth, deployment).

## Layout

| Path | What it is |
|---|---|
| `bharatverse_app/` | Flutter app: home, article, archive, search, likes, sign-in and password reset, offline reading |
| `backend/` | FastAPI service over Supabase: articles, search, likes, auth; rate limiting and JSON request logs |
| `scrapper/` | Content pipeline: scrape (Wikipedia, archive.org, New World Encyclopedia), generate, validate, publish |
| `common/` | Shared models, LLM provider and JSON logging |
| `docs/` | Requirements, design, roadmap and the business requirements document |
| `scripts/` | Dev helpers, including running the app on a phone ([README](scripts/README.md)) |
| `tools/` | Optional dev tools: `local-stack/`, a local Supabase stand-in, and `agent-queue/`, a runner that executes specs with a local model |

## Get started

You need Python 3.12, the Flutter SDK (stable channel) and a [Supabase](https://supabase.com) project.

1. **Supabase.** Run [`backend/database/schema.sql`](backend/database/schema.sql) in the SQL editor and create a public
   Storage bucket named `articles`. (To try things without a hosted project, [`tools/local-stack`](tools/local-stack/README.md)
   runs a local stand-in.) For password-reset emails, add the app's URL under Authentication > URL
   Configuration > Redirect URLs.
2. **Configuration.** `cp .env.example .env` and fill in the Supabase keys and the key for your LLM provider. The app has
   its own copy of the project URL and anon key in `bharatverse_app/lib/config.dart`.
3. **Python.** `python3.12 -m venv .venv && source .venv/bin/activate`, then
   `pip install -r backend/requirements.txt -r scrapper/requirements.txt` and `playwright install chromium`.
4. **Run it.** `./scripts/dev.sh` starts the API on :8000 and the web app on :8765. Each package's README covers running
   it alone, including on a phone ([app](bharatverse_app/README.md)).
5. **Publish an article.** `python scrapper/scrapper_main.py --count 1` (it calls the LLM, which costs money).

## Checks

`./build.sh --check` runs everything CI runs without editing files: formatting, lint, and each package's tests with an
85% coverage gate. `git config core.hooksPath scripts/git-hooks` runs it before every push, and `./scripts/doctor.sh`
reports what is missing from your setup. [AGENTS.md](AGENTS.md) lists the individual commands and the repo's
conventions.

## Documentation

- [Requirements](docs/requirements.md), [design](docs/design.md), [roadmap](docs/roadmap.md)
- [Business requirements](docs/BharatVerse%20MVP%20BRD.md)
- [AGENTS.md](AGENTS.md): guide for AI agents working in this repo

## License

See [LICENSE](LICENSE).
