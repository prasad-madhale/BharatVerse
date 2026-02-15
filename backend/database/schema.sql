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
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT,
    oauth_provider TEXT,
    oauth_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    last_login TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_oauth ON users(oauth_provider, oauth_id) 
    WHERE oauth_provider IS NOT NULL;

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

-- Article embeddings for semantic search (optional)
-- NOTE: This table requires pgvector extension. 
-- If you get an error about "vector" type, skip this table for now.
-- You can enable pgvector later in Supabase dashboard under Database > Extensions
CREATE TABLE IF NOT EXISTS article_embeddings (
    article_id TEXT PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE,
    embedding TEXT NOT NULL,  -- Store as JSON array for now (can migrate to vector type later)
    model TEXT NOT NULL,  -- 'claude-3-embedding' or 'text-embedding-ada-002'
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_embeddings_article ON article_embeddings(article_id);

-- Enable Row Level Security (RLS)
ALTER TABLE articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE search_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE article_embeddings ENABLE ROW LEVEL SECURITY;

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
CREATE POLICY "Users can view own profile" 
    ON users FOR SELECT 
    USING (auth.uid() = id);

CREATE POLICY "Users are insertable by service role" 
    ON users FOR INSERT 
    WITH CHECK (auth.role() = 'service_role');

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

-- RLS Policies for article embeddings (public read, service role write)
CREATE POLICY "Article embeddings are viewable by everyone" 
    ON article_embeddings FOR SELECT 
    USING (true);

CREATE POLICY "Article embeddings are insertable by service role" 
    ON article_embeddings FOR INSERT 
    WITH CHECK (auth.role() = 'service_role');

-- Create full-text search index using PostgreSQL's built-in text search
CREATE INDEX IF NOT EXISTS idx_articles_fts ON articles 
    USING GIN(to_tsvector('english', title || ' ' || summary));

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
