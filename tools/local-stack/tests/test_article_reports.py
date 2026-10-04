"""
`article_reports` takes a report from anyone, under their own user id or none, and gives nothing back to the public or
signed-in roles; the migration adds it to an older project the same way schema.sql does, and can be run twice. Needs the
stand-in's Postgres running; skipped without it.
"""

import json
from pathlib import Path

import pg8000.exceptions
import pytest

from pgscratch import SCHEMA, apply, connect, database_name

MIGRATION = Path(__file__).resolve().parents[3] / "backend" / "database" / "migrations" / "2026-10-article-reports.sql"
ME = "11111111-1111-1111-1111-111111111111"
OTHER = "22222222-2222-2222-2222-222222222222"
FILE = "INSERT INTO article_reports (article_id, user_id, reason, note) VALUES ('a1', {user}, '{reason}', {note})"


@pytest.fixture
def db(new_database):
    db = new_database(SCHEMA.read_text())
    db.run("INSERT INTO articles (id, title, summary, date, reading_time_minutes, author, tags, content_file_path) "
           "VALUES ('a1', 'T', 'S', '2026-01-01', 5, 'x', '[]', 'p')")
    for user in (ME, OTHER):
        db.run("INSERT INTO auth.users (id, email, encrypted_password) VALUES (:id, :email, 'x')",
               id=user, email=f"{user[:4]}@example.com")
    return db


def run_as(db, role, sql, user=None):
    """Runs `sql` as PostgREST would for `role`, signed in as `user` if given."""
    conn = connect(database_name(db))
    try:
        if user:
            conn.run("SELECT set_config('request.jwt.claims', :claims, false)",
                     claims=json.dumps({"sub": user, "role": role}))
        conn.run(f"SET ROLE {role}")
        return conn.run(sql)
    finally:
        conn.close()


def file(db, role, *, as_user=None, user_id=None, reason="factual", note=None):
    user = f"'{user_id}'" if user_id else "NULL"
    note = f"'{note}'" if note is not None else "NULL"
    run_as(db, role, FILE.format(user=user, reason=reason, note=note), as_user)


def reports(db):
    return db.run("SELECT user_id::text, reason, note FROM article_reports ORDER BY created_at, reason")


def test_anyone_files_a_report_and_a_signed_in_reader_may_sign_it(db):
    file(db, "anon", reason="image", note="Wrong fort")
    file(db, "authenticated", as_user=ME, user_id=ME, reason="factual")
    file(db, "authenticated", as_user=ME, reason="other")

    assert {tuple(row) for row in reports(db)} == {(None, "image", "Wrong fort"), (ME, "factual", None), (None, "other", None)}


@pytest.mark.parametrize("role, as_user, user_id", [
    ("anon", None, ME),               # the public key cannot claim to be anyone
    ("authenticated", ME, OTHER),     # nor a reader be someone else
])
def test_nobody_files_under_someone_elses_id(db, role, as_user, user_id):
    with pytest.raises(pg8000.exceptions.DatabaseError, match="row-level security"):
        file(db, role, as_user=as_user, user_id=user_id)
    assert reports(db) == []


@pytest.mark.parametrize("role", ["anon", "authenticated"])
@pytest.mark.parametrize("sql", [
    "SELECT * FROM article_reports",
    "UPDATE article_reports SET note = 'x'",
    "DELETE FROM article_reports",
])
def test_reports_cannot_be_read_changed_or_removed_with_the_app_keys(db, role, sql):
    file(db, "anon")
    with pytest.raises(pg8000.exceptions.DatabaseError, match="permission denied for table article_reports"):
        run_as(db, role, sql, ME if role == "authenticated" else None)
    assert len(reports(db)) == 1


@pytest.mark.parametrize("kwargs", [{"reason": "spam"}, {"note": "x" * 1001}])
def test_an_unknown_reason_or_an_overlong_note_is_refused(db, kwargs):
    with pytest.raises(pg8000.exceptions.DatabaseError, match="check constraint"):
        file(db, "anon", **kwargs)


def test_a_report_outlives_its_authors_account_without_their_id(db):
    file(db, "authenticated", as_user=ME, user_id=ME, reason="offensive")

    run_as(db, "authenticated", "SELECT delete_my_account()", ME)

    assert reports(db) == [[None, "offensive", None]]


def test_the_migration_adds_the_table_like_schema_sql_and_can_be_run_twice(new_database):
    def shape(conn):
        def rows(sql):
            return sorted(tuple(row) for row in conn.run(sql))

        return {
            "columns": rows("SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns "
                            "WHERE table_name = 'article_reports'"),
            "checks": rows("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'article_reports'::regclass"),
            "indexes": rows("SELECT indexname FROM pg_indexes WHERE tablename = 'article_reports'"),
            "policies": rows("SELECT policyname, cmd, roles::text, with_check FROM pg_policies "
                             "WHERE tablename = 'article_reports'"),
            "grants": rows("SELECT grantee, privilege_type, column_name FROM information_schema.column_privileges "
                           "WHERE table_name = 'article_reports' AND grantee IN ('anon', 'authenticated')"),
            "table_grants": rows("SELECT grantee, privilege_type FROM information_schema.table_privileges "
                                 "WHERE table_name = 'article_reports' AND grantee IN ('anon', 'authenticated')"),
            "rls": conn.run("SELECT relrowsecurity FROM pg_class WHERE relname = 'article_reports'"),
        }

    fresh = new_database(SCHEMA.read_text())
    older = new_database(SCHEMA.read_text())
    apply(older, "DROP TABLE article_reports;")

    migration = MIGRATION.read_text()
    apply(older, migration)
    apply(older, migration)

    assert shape(older) == shape(fresh)
    assert shape(fresh)["rls"] == [[True]]
    assert shape(fresh)["table_grants"] == []
