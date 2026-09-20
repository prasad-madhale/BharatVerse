# Human-gated work

The agent must not attempt these. Each needs live credentials, money, an external party, or a product decision.

## Needs live Supabase access

- **Apply the `search_vector` migration.** `backend/database/schema.sql` on the search branch adds a generated
  column and a GIN index that have never been run against the live project. Until they are, every search request
  fails in Postgres, however correct the Python is.
- **Confirm a real search round-trips.** TASK-001 proves the request shape offline. Only a live call proves
  PostgREST accepts it. Try a two-word query.
- **Likes end to end.** TASK-004 and TASK-005 are unit-tested against a real query builder, not a live database.
  The service-role write path bypassing row-level security is correct in theory and unproven in practice.

## Costs money or writes to production

- **Running the daily pipeline.** Each run makes real LLM calls and inserts a real article. Run it once by hand
  from the GitHub Actions tab to prove the secrets and setup work. It has never run there.
- **Re-enabling the daily cron.** The roadmap says not to without discussing first. That still stands.

## Needs an external party

- **Google and Facebook OAuth registration.** Review takes days.
- **App store preparation.** Icons, signing, review lead time, iOS especially.

## Needs a product decision

- **How search and likes reach the app.** The Flutter client reads Supabase directly and bypasses the FastAPI
  backend. Search and likes were built as backend endpoints. Either the app starts calling the backend, which
  means picking a host and writing a Dockerfile, or these features are reimplemented client-side against
  PostgREST. No mobile task can be specified until this is settled.
- **Whether semantic search stays in the MVP.** The roadmap has carried this open question since Phase 2.
- **The default LLM provider.** `common/config.py` defaults to `gemini`; only the daily workflow picks `anthropic`.
  TASK-008 documents this. Changing the default changes what the next run costs, so a person decides.
- **Autocomplete.** The `search_suggestions` table has no unique index on `(term, category)`, so repeated saves
  would duplicate rows. Adding one edits `schema.sql`, which the agent must not touch.

## Blocked by the environment

- **Flutter work** (likes button, search screen, offline cache). There is no Flutter SDK on this machine, so the
  agent could not verify any of it. Add tasks for it on a machine with Flutter, after the decision above.
- **Merging and pushing.** The agent commits to `agent/queue` and stops. A person reviews the branch and pushes.
