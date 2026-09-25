"""
backend/database/migrations/2026-09-saved-articles.sql adds `saved_articles` to an older project,
matches schema.sql, and can be run twice. Needs the stand-in's Postgres running; skipped without it.
"""

from pathlib import Path

from pgscratch import SCHEMA, apply

MIGRATION = Path(__file__).resolve().parents[3] / "backend" / "database" / "migrations" / "2026-09-saved-articles.sql"

# Dropping the table takes its indexes and policies with it (they belong to it, not the other way
# round), which is everything schema.sql's saved_articles section adds -- so this alone simulates
# a project made before this migration existed.
OLDER_PROJECT = "DROP TABLE saved_articles;"


def objects(conn):
    def names(sql):
        return sorted(row[0] for row in conn.run(sql))

    return {
        "tables": names("SELECT tablename FROM pg_tables WHERE schemaname = 'public'"),
        "indexes": names("SELECT indexname FROM pg_indexes WHERE schemaname = 'public'"),
        "policies": names("SELECT tablename || '.' || policyname FROM pg_policies WHERE schemaname = 'public'"),
        "columns": names("SELECT table_name || '.' || column_name FROM information_schema.columns "
                          "WHERE table_schema = 'public' AND table_name = 'saved_articles'"),
    }


def test_the_migration_adds_saved_articles_matching_schema_sql_and_can_be_run_twice(new_database):
    fresh = new_database(SCHEMA.read_text())

    older = new_database(SCHEMA.read_text())
    apply(older, OLDER_PROJECT)
    assert older.run("SELECT to_regclass('saved_articles')") == [[None]]

    migration = MIGRATION.read_text()
    apply(older, migration)
    apply(older, migration)

    assert objects(older) == objects(fresh)
    assert older.run("SELECT relrowsecurity FROM pg_class WHERE relname = 'saved_articles'") == [[True]]
