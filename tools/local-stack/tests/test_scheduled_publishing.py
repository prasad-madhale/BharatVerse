"""
The public sees an article from its date in India on, unless it is withdrawn: through the table, search and the search
suggestions, while the service role (the pipeline) still sees everything. The migration brings an older project to what
schema.sql makes, and can be run twice. Needs the stand-in's Postgres running; skipped without it.
"""

import json
import sys
from datetime import timedelta
from pathlib import Path

import pytest

from pgscratch import SCHEMA, apply, connect, database_name

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from common.publishing import ist_today  # noqa: E402

MIGRATION = Path(__file__).resolve().parents[3] / "backend" / "database" / "migrations" / "2026-10-scheduled-publishing.sql"
TODAY = ist_today()


def add(db, article_id, title, days_from_today=0, status=None):
    db.run("INSERT INTO articles (id, title, summary, date, reading_time_minutes, author, tags, content_file_path"
           + (", status" if status else "") + ") VALUES (:id, :title, 'S', :date, 5, 'x', '[]', 'p'"
           + (", :status" if status else "") + ")",
           id=article_id, title=title, date=TODAY + timedelta(days=days_from_today),
           **({"status": status} if status else {}))


@pytest.fixture
def db(new_database):
    db = new_database(SCHEMA.read_text())
    add(db, "past", "Ashoka the Great", -3)
    add(db, "today", "Ashoka's Edicts", 0)
    add(db, "tomorrow", "Ashoka at Kalinga", 1)
    add(db, "withdrawn", "Ashoka and Buddhism", -1, status="withdrawn")
    return db


def run_as(db, role, sql, **params):
    """Runs `sql` as PostgREST would for `role`."""
    conn = connect(database_name(db))
    try:
        if role == "authenticated":
            conn.run("SELECT set_config('request.jwt.claims', :claims, false)",
                     claims=json.dumps({"sub": "11111111-1111-1111-1111-111111111111", "role": role}))
        conn.run(f"SET ROLE {role}")
        return conn.run(sql, **params)
    finally:
        conn.close()


def ids(rows):
    return sorted(row[0] for row in rows)


def suggested(db, prefix):
    return [row[0] for row in run_as(db, "anon", "SELECT term FROM autocomplete_suggestions(:p, 20)", p=prefix)]


def test_the_database_and_the_pipeline_agree_on_the_day_in_india(db):
    assert db.run("SELECT ist_today()")[0][0] == ist_today()


@pytest.mark.parametrize("role", ["anon", "authenticated"])
def test_the_public_sees_an_article_from_its_day_on_unless_withdrawn(db, role):
    assert ids(run_as(db, role, "SELECT id FROM articles")) == ["past", "today"]


def test_the_service_role_still_sees_scheduled_and_withdrawn_articles(db):
    assert ids(run_as(db, "service_role", "SELECT id FROM articles")) == ["past", "today", "tomorrow", "withdrawn"]


@pytest.mark.parametrize("role", ["anon", "authenticated", "service_role"])
def test_search_finds_only_live_articles_whoever_asks(db, role):
    assert ids(run_as(db, role, "SELECT id FROM search_articles('Ashoka', 20)")) == ["past", "today"]


def test_suggestions_come_from_live_articles_only(db):
    assert sorted(suggested(db, "ashoka")) == ["Ashoka the Great", "Ashoka's Edicts"]


def test_withdrawing_an_article_takes_it_down_at_once(db):
    run_as(db, "service_role", "UPDATE articles SET status = 'withdrawn' WHERE id = 'today'")

    assert ids(run_as(db, "anon", "SELECT id FROM articles")) == ["past"]
    assert ids(run_as(db, "anon", "SELECT id FROM search_articles('Edicts', 20)")) == []
    assert suggested(db, "ashoka's") == []


def test_publishing_an_article_brings_it_back(db):
    run_as(db, "service_role", "UPDATE articles SET status = 'published' WHERE id = 'withdrawn'")

    assert "withdrawn" in ids(run_as(db, "anon", "SELECT id FROM articles"))
    assert suggested(db, "ashoka and") == ["Ashoka and Buddhism"]


def test_status_is_published_or_withdrawn(db):
    with pytest.raises(Exception, match="articles_status_check"):
        db.run("UPDATE articles SET status = 'draft' WHERE id = 'past'")


def test_the_migration_brings_an_older_project_to_schema_sql_and_can_be_run_twice(new_database):
    def shape(conn):
        def rows(sql):
            return sorted(tuple(row) for row in conn.run(sql))

        return {
            "status": rows("SELECT data_type, is_nullable, column_default FROM information_schema.columns "
                           "WHERE table_name = 'articles' AND column_name = 'status'"),
            "checks": rows("SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint "
                           "WHERE conrelid = 'articles'::regclass AND contype = 'c'"),
            "policies": rows("SELECT policyname, cmd, qual, with_check FROM pg_policies WHERE tablename = 'articles'"),
            "functions": rows("SELECT proname, pg_get_functiondef(oid) FROM pg_proc WHERE proname IN "
                              "('ist_today', 'search_articles', 'rebuild_search_suggestions')"),
            "rebuild_rights": rows("SELECT grantee, privilege_type FROM information_schema.routine_privileges "
                                   "WHERE routine_name = 'rebuild_search_suggestions'"),
        }

    fresh = new_database(SCHEMA.read_text())
    # Before this migration: anyone saw every row, and search and the suggestions took every row
    older = new_database(SCHEMA.read_text()
                         .replace(" AND a.status = 'published' AND a.date <= ist_today()", "")
                         .replace("FROM articles WHERE status = 'published' AND date <= ist_today()", "FROM articles"))
    apply(older, """
        DROP POLICY "Published articles are viewable by everyone" ON articles;
        CREATE POLICY "Articles are viewable by everyone" ON articles FOR SELECT USING (true);
        ALTER TABLE articles DROP COLUMN status;
        DROP FUNCTION ist_today();
    """)
    older.run("INSERT INTO articles (id, title, summary, date, reading_time_minutes, author, tags, content_file_path) "
              "VALUES ('old', 'Ashoka the Great', 'S', '2026-01-01', 5, 'x', '[]', 'p')")

    migration = MIGRATION.read_text()
    apply(older, migration)
    apply(older, migration)

    assert shape(older) == shape(fresh)
    assert older.run("SELECT status FROM articles WHERE id = 'old'") == [["published"]]
    add(older, "tomorrow", "Ashoka at Kalinga", 1)
    assert ids(run_as(older, "anon", "SELECT id FROM articles")) == ["old"]
    assert suggested(older, "ashoka at") == []
