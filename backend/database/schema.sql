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

-- Search suggestions for autocomplete
CREATE TABLE IF NOT EXISTS search_suggestions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    term TEXT NOT NULL,
    category TEXT NOT NULL,  -- 'title', 'tag', 'person', 'event', 'period'
    frequency INTEGER DEFAULT 1,  -- How often this term appears
    article_count INTEGER DEFAULT 0,  -- Number of articles with this term
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_search_suggestions_term ON search_suggestions(term);
CREATE INDEX IF NOT EXISTS idx_search_suggestions_category ON search_suggestions(category);
CREATE INDEX IF NOT EXISTS idx_search_suggestions_frequency ON search_suggestions(frequency DESC);

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

-- RLS Policies for search suggestions (public read, service role write)
CREATE POLICY "Search suggestions are viewable by everyone" 
    ON search_suggestions FOR SELECT 
    USING (true);

CREATE POLICY "Search suggestions are insertable by service role" 
    ON search_suggestions FOR INSERT 
    WITH CHECK (auth.role() = 'service_role');

-- Full-text search over title, tags and summary, weighted so a title term counts most (A), then a tag (B),
-- then a summary term (C). Tags are lowercase hyphenated slugs, which the parser splits, so a search for
-- "medieval" or "empire" finds "medieval-india" and "gupta-empire". A generated, stored column (rather
-- than an index on a bare to_tsvector(...) expression) is required here
-- because PostgREST's text_search() filter -- what supabase-py's
-- .text_search() ultimately sends -- takes a column name, not an
-- expression; it can't reference an expression index directly.
-- A database that already has an earlier version of this column must drop it first
-- (ALTER TABLE articles DROP COLUMN search_vector) for the new definition to apply.
ALTER TABLE articles ADD COLUMN IF NOT EXISTS search_vector tsvector
    GENERATED ALWAYS AS (
        setweight(to_tsvector('english', title), 'A') ||
        setweight(to_tsvector('english', tags), 'B') ||
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

CREATE TRIGGER update_search_suggestions_updated_at BEFORE UPDATE ON search_suggestions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
