"""
`delete_my_account()` deletes only the caller, with their likes and saves, and only a signed-in user may call it; the
migration adds it to an older project the same way schema.sql does, and can be run twice. Needs the stand-in's Postgres
running; skipped without it.
"""

import json
from pathlib import Path

import pg8000.exceptions
import pytest

from pgscratch import SCHEMA, apply, connect, database_name

MIGRATION = Path(__file__).resolve().parents[3] / "backend" / "database" / "migrations" / "2026-10-delete-account.sql"
ME = "11111111-1111-1111-1111-111111111111"
OTHER = "22222222-2222-2222-2222-222222222222"


def seed(db):
    db.run("INSERT INTO articles (id, title, summary, date, reading_time_minutes, author, tags, content_file_path) "
           "VALUES ('a1', 'T', 'S', '2026-01-01', 5, 'x', '[]', 'p')")
    for user in (ME, OTHER):
        db.run("INSERT INTO auth.users (id, email, encrypted_password) VALUES (:id, :email, 'x')",
               id=user, email=f"{user[:4]}@example.com")
        db.run("INSERT INTO likes (user_id, article_id) VALUES (:id, 'a1')", id=user)
        db.run("INSERT INTO saved_articles (user_id, article_id) VALUES (:id, 'a1')", id=user)


def call_as(db, role, user=None):
    """Calls delete_my_account() as PostgREST would for `role`, signed in as `user` if given."""
    conn = connect(database_name(db))
    try:
        if user:
            conn.run("SELECT set_config('request.jwt.claims', :claims, false)",
                     claims=json.dumps({"sub": user, "role": role}))
        conn.run(f"SET ROLE {role}")
        conn.run("SELECT delete_my_account()")
    finally:
        conn.close()


def remaining(db, table, column="user_id"):
    return sorted(str(row[0]) for row in db.run(f"SELECT {column} FROM {table}"))


def test_a_signed_in_user_deletes_only_themselves_with_their_likes_and_saves(new_database):
    db = new_database(SCHEMA.read_text())
    seed(db)

    call_as(db, "authenticated", ME)

    assert remaining(db, "auth.users", "id") == [OTHER]
    assert remaining(db, "users", "id") == [OTHER]
    assert remaining(db, "likes") == [OTHER]
    assert remaining(db, "saved_articles") == [OTHER]
    assert remaining(db, "articles", "id") == ["a1"]


def test_the_public_key_cannot_call_it(new_database):
    db = new_database(SCHEMA.read_text())
    seed(db)

    with pytest.raises(pg8000.exceptions.DatabaseError, match="permission denied for function"):
        call_as(db, "anon")
    assert remaining(db, "auth.users", "id") == [ME, OTHER]


def test_signed_in_without_a_user_id_deletes_nothing(new_database):
    db = new_database(SCHEMA.read_text())
    seed(db)

    call_as(db, "authenticated")

    assert remaining(db, "auth.users", "id") == [ME, OTHER]


def test_the_migration_adds_it_like_schema_sql_and_can_be_run_twice(new_database):
    def shape(conn):
        return conn.run(
            "SELECT p.prosecdef, p.proconfig, pg_get_functiondef(p.oid), "
            "has_function_privilege('anon', p.oid, 'execute'), "
            "has_function_privilege('authenticated', p.oid, 'execute') "
            "FROM pg_proc p WHERE p.proname = 'delete_my_account'")

    fresh = new_database(SCHEMA.read_text())
    older = new_database(SCHEMA.read_text())
    apply(older, "DROP FUNCTION delete_my_account();")
    assert shape(older) == []

    migration = MIGRATION.read_text()
    apply(older, migration)
    apply(older, migration)

    assert shape(older) == shape(fresh)
    assert shape(fresh)[0][0] is True  # SECURITY DEFINER
    assert shape(fresh)[0][3:] == [False, True]
