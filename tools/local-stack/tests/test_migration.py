"""
backend/database/migrations/2026-09-search-and-autocomplete.sql brings an older project up to date, can be run twice, and
matches schema.sql. Needs the stand-in's Postgres running (see pgscratch.py); skipped without it.
"""

import json

import pg8000.exceptions
import pytest

from pgscratch import MIGRATION, SCHEMA, apply, connect, database_name

# What a project made from the schema before search and autocomplete has: no search column or function, the unused earlier
# suggestions table with its policies, the unused embeddings table, and the write rights every table then had
OLDER_PROJECT = """
DROP TRIGGER articles_refresh_search_suggestions ON articles;
DROP FUNCTION autocomplete_suggestions(text, int);
DROP FUNCTION rebuild_search_suggestions();
DROP FUNCTION refresh_search_suggestions();
DROP TABLE search_suggestions;
CREATE TABLE search_suggestions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), term TEXT NOT NULL, category TEXT NOT NULL, frequency INTEGER DEFAULT 1,
    article_count INTEGER DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
ALTER TABLE search_suggestions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Search suggestions are viewable by everyone" ON search_suggestions FOR SELECT USING (true);
CREATE POLICY "Search suggestions are insertable by service role" ON search_suggestions FOR INSERT WITH CHECK (auth.role() = 'service_role');
CREATE TRIGGER update_search_suggestions_updated_at BEFORE UPDATE ON search_suggestions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TABLE article_embeddings (id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), article_id TEXT REFERENCES articles(id), embedding TEXT);
DROP FUNCTION search_articles(text, int);
ALTER TABLE articles DROP COLUMN search_vector;
CREATE INDEX idx_articles_fts ON articles USING GIN (to_tsvector('english', title || ' ' || summary));
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON articles TO anon, authenticated;
"""
ARTICLES = [("a1", "The Mauryan Empire: India's First Great Dynasty", ["mauryan-empire", "ancient-india", "ashoka"]),
            ("a2", "The Indus Valley Civilisation", ["indus-valley", "ancient-india", "harappa"]),
            ("a3", "The Cholas and the Sea", ["chola-dynasty", "medieval-india", "maritime-history"]),
            ("a4", "The Revolt: Uprising of 1857", ["revolt-1857", "covid-19"]),
            ("a5", "Ashoka -Kalinga Aftermath", [])]
PREFIXES = ["m", "ma", "the", "the m", "ind", "chola", "a", "ancient", "revolt", "co", "ash", "zzz", "  MAUR  "]
INSERT = ("INSERT INTO articles (id, title, summary, date, reading_time_minutes, author, tags, content_file_path) "
          "VALUES (:i, :t, 'A summary.', '2026-07-09', 5, 'x', CAST(:g AS jsonb), 'p')")


def add_articles(conn):
    for article_id, title, tags in ARTICLES:
        conn.run(INSERT, i=article_id, t=title, g=json.dumps(tags))


def behaviour(conn):
    """What a reader could see: the suggestions, what each prefix offers, and what a search finds."""
    return {
        "table": conn.run("SELECT term_key, term, category, article_count FROM search_suggestions ORDER BY term_key"),
        "lookups": {p: conn.run("SELECT term FROM autocomplete_suggestions(:p, 10)", p=p) for p in PREFIXES},
        "searches": {q: conn.run("SELECT id FROM search_articles(:q, 10)", q=q) for q in ("chola", "empire", "mauryan empire", "1857")},
    }


def objects(conn):
    """Everything in the schema by kind and name, so a leftover (or a missing) index, table, function, trigger or policy shows."""
    def names(sql):
        return sorted(row[0] for row in conn.run(sql))

    return {
        "tables": names("SELECT tablename FROM pg_tables WHERE schemaname = 'public'"),
        "indexes": names("SELECT indexname FROM pg_indexes WHERE schemaname = 'public'"),
        "functions": names("SELECT proname || '(' || pg_get_function_identity_arguments(oid) || ')' FROM pg_proc "
                           "WHERE pronamespace = 'public'::regnamespace"),
        "triggers": names("SELECT tgrelid::regclass || '.' || tgname FROM pg_trigger WHERE NOT tgisinternal"),
        "policies": names("SELECT tablename || '.' || policyname FROM pg_policies WHERE schemaname = 'public'"),
        "columns": names("SELECT table_name || '.' || column_name FROM information_schema.columns WHERE table_schema = 'public'"),
    }


def as_anon(conn, sql):
    other = connect(database_name(conn))
    try:
        other.run("SET ROLE anon")
        return other.run(sql)
    finally:
        other.close()


def test_the_migration_brings_an_older_project_to_what_schema_sql_makes_and_can_be_run_twice(new_database):
    fresh = new_database(SCHEMA.read_text())
    add_articles(fresh)

    older = new_database(SCHEMA.read_text())
    apply(older, OLDER_PROJECT)
    add_articles(older)
    assert older.run("SELECT 1 FROM pg_proc WHERE proname = 'search_articles'") == []
    assert older.run("SELECT to_regclass('article_embeddings')") != [[None]]

    migration = MIGRATION.read_text()
    apply(older, migration)
    apply(older, migration)

    assert behaviour(older) == behaviour(fresh)
    assert objects(older) == objects(fresh)
    assert older.run("SELECT to_regclass('article_embeddings')") == [[None]]
    assert older.run("SELECT relrowsecurity FROM pg_class WHERE relname = 'search_suggestions'") == [[True]]
    with pytest.raises(pg8000.exceptions.DatabaseError, match="permission denied for table articles"):
        as_anon(older, "DELETE FROM articles WHERE id = 'a1'")
    older.run(INSERT, i="new", t="Zzqnew Article", g="[]")  # publishing works, and its suggestion follows at once
    assert older.run("SELECT term FROM autocomplete_suggestions('zzqnew')") == [["Zzqnew Article"]]


def test_the_migration_holds_the_same_statements_as_schema_sql():
    """Each function, the trigger and the table it sets up are copied from schema.sql word for word."""
    schema, migration = SCHEMA.read_text(), MIGRATION.read_text()

    def block(text, start, end):
        return text[text.index(start):text.index(end, text.index(start)) + len(end)]

    for start, end in [("CREATE OR REPLACE FUNCTION search_articles", "LIMIT match_limit\n$$;"),
                       ("DROP TABLE IF EXISTS search_suggestions;", "(term_key text_pattern_ops);"),
                       ("CREATE OR REPLACE FUNCTION rebuild_search_suggestions()", "LIMIT least(greatest(coalesce(match_limit, 10), 0), 20)\n$$;"),
                       ("ALTER TABLE articles ADD COLUMN IF NOT EXISTS search_vector", "USING GIN(search_vector);")]:
        assert block(schema, start, end) in migration, start
