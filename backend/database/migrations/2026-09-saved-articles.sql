-- Adds the `saved_articles` table (bookmarks): paste it into the SQL editor and run it once. It can
-- be run again, and does not touch any other table.
--
-- Copied from schema.sql's saved_articles section word for word (see tools/local-stack/tests).

CREATE TABLE IF NOT EXISTS saved_articles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    article_id TEXT NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_saved_articles_user_article ON saved_articles(user_id, article_id);
CREATE INDEX IF NOT EXISTS idx_saved_articles_user ON saved_articles(user_id);
CREATE INDEX IF NOT EXISTS idx_saved_articles_article ON saved_articles(article_id);

ALTER TABLE saved_articles ENABLE ROW LEVEL SECURITY;

-- Postgres has no CREATE POLICY IF NOT EXISTS, so drop-then-create is what makes this idempotent.
DROP POLICY IF EXISTS "Users can view own saves" ON saved_articles;
CREATE POLICY "Users can view own saves"
    ON saved_articles FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own saves" ON saved_articles;
CREATE POLICY "Users can insert own saves"
    ON saved_articles FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own saves" ON saved_articles;
CREATE POLICY "Users can delete own saves"
    ON saved_articles FOR DELETE
    USING (auth.uid() = user_id);
