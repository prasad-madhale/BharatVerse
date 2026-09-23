-- Brings a Supabase project made from an earlier schema.sql up to date with search and autocomplete: paste it into the SQL
-- editor and run it once. It can be run again, and does not touch articles, users or likes.
--
-- It is schema.sql's search and suggestions sections, with the statements that fail on a table that already exists left out,
-- so it must be kept in step with them (tools/local-stack/tests/test_migration.py checks that it is). Whole-file runs of
-- schema.sql only suit a new project: the SQL editor runs a file as one transaction, and it stops at the first policy or
-- trigger that exists.

-- Full-text search: drop the earlier title-and-summary version of the column, if any, then add the weighted one
ALTER TABLE articles DROP COLUMN IF EXISTS search_vector;

-- Full-text search over title, tags and summary, weighted so a title term counts most (A), then a tag (B),
-- then a summary term (C). Tags are lowercase hyphenated slugs, which the parser splits, so a search for
-- "medieval" or "empire" finds "medieval-india" and "gupta-empire". A hyphen right before a digit tokenizes
-- with it instead ("covid-19" indexes as "covid" and "-19", not "19"), so the tag text is indexed a second
-- time with such hyphens turned to spaces, letting "covid 19" find it too. A generated, stored column (rather
-- than an index on a bare to_tsvector(...) expression) is required here
-- because PostgREST's text_search() filter -- what supabase-py's
-- .text_search() ultimately sends -- takes a column name, not an
-- expression; it can't reference an expression index directly.
-- A database that already has an earlier version of this column must drop it first
-- (ALTER TABLE articles DROP COLUMN search_vector) for the new definition to apply.
ALTER TABLE articles ADD COLUMN IF NOT EXISTS search_vector tsvector
    GENERATED ALWAYS AS (
        setweight(to_tsvector('english', title), 'A') ||
        setweight(
            to_tsvector('english', tags) ||
            to_tsvector('english', regexp_replace(tags::text, '-(?=[0-9])', ' ', 'g')),
            'B'
        ) ||
        setweight(to_tsvector('english', summary), 'C')
    ) STORED;

CREATE INDEX IF NOT EXISTS idx_articles_search_vector ON articles USING GIN(search_vector);

-- Search ranked by relevance, called as rpc/search_articles by the backend and the app (a PostgREST
-- filter cannot rank). The vector's weights make a title match beat a tag match, and a tag match beat a
-- few passing mentions in the summary; date, then created_at and id, break ties so the order is stable.
CREATE OR REPLACE FUNCTION search_articles(search_query TEXT, match_limit INT DEFAULT 20)
RETURNS SETOF articles
LANGUAGE sql STABLE
AS $$
    SELECT a.*
    FROM articles a, websearch_to_tsquery('english', search_query) AS q
    WHERE a.search_vector @@ q
    ORDER BY ts_rank_cd(a.search_vector, q) DESC, a.date DESC, a.created_at DESC, a.id DESC
    LIMIT match_limit
$$;

-- Autocomplete: the table (an earlier, unused one is dropped, as are the equally unused article_embeddings and the earlier
-- full-text index that nothing queries), its security, the trigger that keeps it current, and the lookup
DROP TABLE IF EXISTS article_embeddings;
DROP INDEX IF EXISTS idx_articles_fts;

-- Search suggestions for autocomplete: every phrase a reader may type to find an article, once, with how many articles
-- carry it -- each part of a title (split at a colon or a dash, so "The Mauryan Empire: India's First Great Dynasty" gives
-- two), as it is and without a leading "the", "a" or "an", and the tags with hyphens read as spaces ("medieval-india" is
-- "Medieval India"). A reader picks one to search for, so a phrase is kept only if searching for it finds the article it
-- came from (which drops one a search would read as "not"), and it is at most 200 characters. rebuild_search_suggestions() fills the table from `articles` and a trigger runs that after every change to
-- `articles`, so the pipeline needs no extra step and nothing goes stale. It is derived data, so an earlier version of the
-- table (this one replaces an unused one) is simply dropped.
DROP TABLE IF EXISTS search_suggestions;
CREATE TABLE search_suggestions (
    term_key TEXT PRIMARY KEY,       -- lower-cased, whitespace collapsed: what a typed prefix is compared with
    term TEXT NOT NULL,              -- the phrase as shown
    category TEXT NOT NULL,          -- 'tag' if any article carries it as a tag, else 'title'
    article_count INTEGER NOT NULL   -- how many articles carry it
);

-- text_pattern_ops lets a prefix search use the index whatever the database's collation
CREATE INDEX IF NOT EXISTS idx_search_suggestions_prefix ON search_suggestions (term_key text_pattern_ops);

ALTER TABLE search_suggestions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Search suggestions are viewable by everyone"
    ON search_suggestions FOR SELECT
    USING (true);

-- client_min_messages: a phrase of only stop words ("Of The") makes websearch_to_tsquery send a NOTICE to whoever is writing
CREATE OR REPLACE FUNCTION rebuild_search_suggestions()
RETURNS void
LANGUAGE plpgsql SET search_path = public, pg_temp SET client_min_messages = warning
AS $$
BEGIN
    LOCK TABLE search_suggestions IN EXCLUSIVE MODE;  -- one rebuild at a time; readers are not held up
    DELETE FROM search_suggestions;
    INSERT INTO search_suggestions (term_key, term, category, article_count)
    WITH parts AS (
        SELECT a.id, part
        FROM articles a, LATERAL regexp_split_to_table(a.title, '\s*[:\u2013\u2014]+\s*|\s+-\s+') AS part
    ), tags AS (
        SELECT a.id, tag #>> '{}' AS slug
        FROM articles a,
             LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(a.tags) = 'array' THEN a.tags ELSE '[]'::jsonb END) AS tag
        WHERE jsonb_typeof(tag) = 'string'
    ), raw AS (
        -- "medieval-india" reads as "Medieval India"; search_vector indexes a hyphen-before-digit tag both
        -- ways (see schema.sql above it), so this reads right for "covid-19" too
        SELECT t.id, initcap(replace(t.slug, '-', ' ')) AS phrase, 'tag' AS category FROM tags t
        UNION ALL SELECT id, part, 'title' FROM parts
        UNION ALL SELECT id, regexp_replace(part, '^(the|a|an)\s+', '', 'i'), 'title' FROM parts
    ), phrases AS (
        SELECT id, btrim(regexp_replace(phrase, '\s+', ' ', 'g')) AS phrase, category FROM raw
    )
    SELECT lower(p.phrase),
           (array_agg(p.phrase ORDER BY (p.phrase = upper(p.phrase)), (p.phrase = lower(p.phrase)), p.phrase COLLATE "C"))[1],
           min(p.category),
           count(DISTINCT p.id)
    FROM phrases p JOIN articles a ON a.id = p.id
    WHERE char_length(p.phrase) <= 200 AND a.search_vector @@ websearch_to_tsquery('english', p.phrase)
    GROUP BY lower(p.phrase);
END;
$$;

-- SECURITY DEFINER so the writers of `articles` (the service role) need no rights on the suggestions or the functions.
-- The suggestions are derived data, so a rebuild that fails is reported and never stops an article being written.
CREATE OR REPLACE FUNCTION refresh_search_suggestions()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    BEGIN
        PERFORM rebuild_search_suggestions();
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'search_suggestions not rebuilt: %', SQLERRM;
    END;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS articles_refresh_search_suggestions ON articles;
CREATE TRIGGER articles_refresh_search_suggestions
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON articles
    FOR EACH STATEMENT EXECUTE FUNCTION refresh_search_suggestions();

-- Not for the API: the trigger runs them with its owner's rights, whoever wrote the article
REVOKE ALL ON FUNCTION rebuild_search_suggestions(), refresh_search_suggestions()
    FROM PUBLIC, anon, authenticated, service_role;

-- Only that trigger writes the suggestions, and only the service role writes articles. Row-level security already keeps the
-- public key from changing either, but a request it refuses that way still runs its statement, and so the trigger's full
-- rebuild; with no right to write those tables, the request fails at once.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON search_suggestions FROM anon, authenticated, service_role;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON articles FROM anon, authenticated;

-- Autocomplete: the suggestions that start with what was typed (case and extra spaces do not matter), the phrases more
-- articles carry first, then tags before titles, then shorter ones; at most 20, so a null or huge match_limit cannot dump
-- the table. Called as rpc/autocomplete_suggestions by the backend and the app.
CREATE OR REPLACE FUNCTION autocomplete_suggestions(prefix TEXT, match_limit INT DEFAULT 10)
RETURNS TABLE (term TEXT)
LANGUAGE sql STABLE
AS $$
    SELECT s.term
    FROM search_suggestions s,
         (SELECT lower(btrim(regexp_replace(prefix, '\s+', ' ', 'g'))) AS typed) t
    WHERE t.typed <> '' AND starts_with(s.term_key, t.typed)
    ORDER BY s.article_count DESC, (s.category = 'title'), length(s.term), s.term_key COLLATE "C"
    LIMIT least(greatest(coalesce(match_limit, 10), 0), 20)
$$;

-- Fill it from the articles already there
SELECT rebuild_search_suggestions();
