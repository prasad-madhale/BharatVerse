-- Scheduled publishing and takedown (launch plan L15): the public sees an article from its `date` in India on, unless
-- its `status` is 'withdrawn' (set it in the table editor to take an article down). Enable pg_cron first (Database >
-- Extensions) so the search suggestions take in each day's article at midnight IST. Safe to run twice.

ALTER TABLE articles ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'published';
ALTER TABLE articles DROP CONSTRAINT IF EXISTS articles_status_check;
ALTER TABLE articles ADD CONSTRAINT articles_status_check CHECK (status IN ('published', 'withdrawn'));

-- Today's date in India, where the day turns for readers
CREATE OR REPLACE FUNCTION ist_today()
RETURNS date
LANGUAGE sql STABLE
AS $$ SELECT (now() AT TIME ZONE 'Asia/Kolkata')::date $$;

DROP POLICY IF EXISTS "Articles are viewable by everyone" ON articles;
DROP POLICY IF EXISTS "Published articles are viewable by everyone" ON articles;
CREATE POLICY "Published articles are viewable by everyone"
    ON articles FOR SELECT
    USING (status = 'published' AND date <= ist_today());

CREATE OR REPLACE FUNCTION search_articles(search_query TEXT, match_limit INT DEFAULT 20)
RETURNS SETOF articles
LANGUAGE sql STABLE
AS $$
    SELECT a.*
    FROM articles a, websearch_to_tsquery('english', search_query) AS q
    WHERE a.search_vector @@ q AND a.status = 'published' AND a.date <= ist_today()
    ORDER BY ts_rank_cd(a.search_vector, q) DESC, a.date DESC, a.created_at DESC, a.id DESC
    LIMIT match_limit
$$;

-- client_min_messages: a phrase of only stop words ("Of The") makes websearch_to_tsquery send a NOTICE to whoever is writing
CREATE OR REPLACE FUNCTION rebuild_search_suggestions()
RETURNS void
LANGUAGE plpgsql SET search_path = public, pg_temp SET client_min_messages = warning
AS $$
BEGIN
    LOCK TABLE search_suggestions IN EXCLUSIVE MODE;  -- one rebuild at a time; readers are not held up
    DELETE FROM search_suggestions;
    INSERT INTO search_suggestions (term_key, term, category, article_count)
    WITH visible AS (
        -- what the public can read (the policy on articles; this runs as the owner, who bypasses it), so a
        -- scheduled or withdrawn title is never suggested
        SELECT id, title, tags, search_vector FROM articles WHERE status = 'published' AND date <= ist_today()
    ), parts AS (
        SELECT a.id, part
        FROM visible a, LATERAL regexp_split_to_table(a.title, '\s*[:\u2013\u2014]+\s*|\s+-\s+') AS part
    ), tags AS (
        SELECT a.id, tag #>> '{}' AS slug
        FROM visible a,
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
    FROM phrases p JOIN visible a ON a.id = p.id
    WHERE char_length(p.phrase) <= 200 AND a.search_vector @@ websearch_to_tsquery('english', p.phrase)
    GROUP BY lower(p.phrase);
END;
$$;

-- CREATE OR REPLACE keeps a function's rights; repeated so a fresh copy of this file stands on its own
REVOKE ALL ON FUNCTION rebuild_search_suggestions() FROM PUBLIC, anon, authenticated, service_role;

SELECT rebuild_search_suggestions();

-- A scheduled article goes public when the day turns in India, with no write to `articles` to rebuild the suggestions:
-- pg_cron rebuilds them then, at 00:00 IST (18:30 UTC). Supabase: enable it under Database > Extensions first.
-- Without it, they catch up when the next article is written.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule('rebuild-search-suggestions', '30 18 * * *', 'SELECT public.rebuild_search_suggestions()');
    ELSE
        RAISE NOTICE 'pg_cron is not installed: search suggestions will catch up with each day''s article when the next one is written';
    END IF;
END
$$;
