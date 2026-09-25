"""
backend/database/migrations/2026-09-era-field.sql adds `era` to an older project's `articles`
table, matches schema.sql, and can be run twice. Needs the stand-in's Postgres running; skipped
without it.
"""

from pathlib import Path

from pgscratch import SCHEMA, apply

MIGRATION = Path(__file__).resolve().parents[3] / "backend" / "database" / "migrations" / "2026-09-era-field.sql"
INSERT_OLD = ("INSERT INTO articles (id, title, summary, date, reading_time_minutes, author, tags, content_file_path) "
              "VALUES ('a1', 'T', 'S', '2026-07-09', 5, 'x', '[]'::jsonb, 'p')")


def columns(conn):
    return conn.run("SELECT column_name, is_nullable, column_default FROM information_schema.columns "
                     "WHERE table_schema = 'public' AND table_name = 'articles' AND column_name = 'era'")


def test_the_migration_adds_era_matching_schema_sql_and_can_be_run_twice(new_database):
    fresh = new_database(SCHEMA.read_text())
    assert columns(fresh) == [["era", "NO", "''::text"]]

    older = new_database(SCHEMA.read_text().replace(
        "    era TEXT NOT NULL DEFAULT '',  -- short label, e.g. 'Gupta Empire'; '' for pre-era articles\n", ""))
    assert columns(older) == []
    older.run(INSERT_OLD)  # publishing already worked before this column existed

    migration = MIGRATION.read_text()
    apply(older, migration)
    apply(older, migration)

    assert columns(older) == columns(fresh)
    assert older.run("SELECT era FROM articles WHERE id = 'a1'") == [[""]]
