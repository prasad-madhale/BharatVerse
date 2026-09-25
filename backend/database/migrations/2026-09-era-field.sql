-- Adds the `era` column to `articles`: paste it into the SQL editor and run it once. It can be run
-- again, and does not touch any other table.
--
-- Existing rows get '' (the same "unknown" convention search_vector already treats an empty string
-- as an absence of, since to_tsvector('') indexes nothing) until they are backfilled by hand or by
-- reprocess_articles.py.

ALTER TABLE articles ADD COLUMN IF NOT EXISTS era TEXT NOT NULL DEFAULT '';
