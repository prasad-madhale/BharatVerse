-- BharatVerse MVP Database Schema for Supabase (PostgreSQL)
-- Run this in Supabase SQL Editor to create all tables

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Articles metadata
CREATE TABLE IF NOT EXISTS articles (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    date DATE NOT NULL,
    reading_time_minutes INTEGER NOT NULL,
    author TEXT NOT NULL,
    tags JSONB NOT NULL DEFAULT '[]'::jsonb,  -- JSON array
    era TEXT NOT NULL DEFAULT '',  -- short label, e.g. 'Gupta Empire'; '' for pre-era articles
    image_url TEXT,
    content_file_path TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_articles_date ON articles(date DESC);
CREATE INDEX IF NOT EXISTS idx_articles_tags ON articles USING GIN(tags);

-- Users
-- Authentication (email/password + Google/Facebook OAuth) is handled entirely
-- by Supabase Auth (auth.users). This table is a slim profile table that
-- mirrors auth.users for app-specific fields and foreign keys (e.g. likes).
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    last_login TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Automatically create a public.users profile row whenever Supabase Auth
-- creates a new auth.users row (email/password signup or OAuth signup).
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Likes
CREATE TABLE IF NOT EXISTS likes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    article_id TEXT NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_likes_user_article ON likes(user_id, article_id);
CREATE INDEX IF NOT EXISTS idx_likes_user ON likes(user_id);
CREATE INDEX IF NOT EXISTS idx_likes_article ON likes(article_id);

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

-- Enable Row Level Security (RLS)
ALTER TABLE articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE search_suggestions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for articles (public read, service role write)
CREATE POLICY "Articles are viewable by everyone" 
    ON articles FOR SELECT 
    USING (true);

CREATE POLICY "Articles are insertable by service role" 
    ON articles FOR INSERT 
    WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Articles are updatable by service role" 
    ON articles FOR UPDATE 
    USING (auth.role() = 'service_role');

-- RLS Policies for users (users can read their own data)
-- Note: rows are inserted automatically by the on_auth_user_created trigger
-- (SECURITY DEFINER, bypasses RLS), so no INSERT policy is needed here.
CREATE POLICY "Users can view own profile"
    ON users FOR SELECT
    USING (auth.uid() = id);

-- RLS Policies for likes (users can manage their own likes)
CREATE POLICY "Users can view own likes" 
    ON likes FOR SELECT 
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own likes" 
    ON likes FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own likes" 
    ON likes FOR DELETE 
    USING (auth.uid() = user_id);

-- RLS Policies for search suggestions (public read; the trigger's rebuild_search_suggestions() is the only writer)
CREATE POLICY "Search suggestions are viewable by everyone"
    ON search_suggestions FOR SELECT
    USING (true);

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

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger to automatically update updated_at
CREATE TRIGGER update_articles_updated_at BEFORE UPDATE ON articles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Fill the suggestions from the articles already there (nothing to do on a new database)
SELECT rebuild_search_suggestions();
