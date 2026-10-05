-- Adds `article_reports`, which the app's "Report a problem" writes to: paste it into the SQL editor and run it once. It
-- can be run again, and does not touch any other table.
--
-- Copied from schema.sql's article_reports section word for word (see tools/local-stack/tests).

-- Problem reports readers file from an article ("Report a problem"): a factual error, a wrong image, offensive text.
-- Anyone may file one, signed in or not, under their own user id or none; nobody but the owner, in the dashboard, reads
-- them. A report outlives its author's account, without the user id.
CREATE TABLE IF NOT EXISTS article_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id TEXT NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    reason TEXT NOT NULL CHECK (reason IN ('factual', 'image', 'offensive', 'other')),
    note TEXT CHECK (char_length(note) <= 1000),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_article_reports_article ON article_reports(article_id);

ALTER TABLE article_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can file a report as themselves" ON article_reports;
CREATE POLICY "Anyone can file a report as themselves"
    ON article_reports FOR INSERT TO anon, authenticated
    WITH CHECK (user_id IS NULL OR user_id = auth.uid());
REVOKE ALL ON article_reports FROM anon, authenticated;
GRANT INSERT (article_id, user_id, reason, note) ON article_reports TO anon, authenticated;
