"""Tests for the stand-in's own logic: the SQL statement splitter, and the gateway's tokens, passwords and Storage. No database."""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import gateway  # noqa: E402
from sqlrun import statements  # noqa: E402

SCHEMA = Path(__file__).resolve().parents[3] / "backend" / "database" / "schema.sql"


def test_splits_on_semicolons_and_drops_comments_and_blank_statements():
    script = "-- a comment; with a semicolon\nSELECT 1;\n\n;\nSELECT 2 -- trailing\n"
    assert list(statements(script)) == ["SELECT 1", "SELECT 2"]


def test_keeps_semicolons_inside_quotes_and_dollar_quoted_bodies_whole():
    script = "SELECT 'a;b', 'it''s; fine';\nCREATE FUNCTION f() RETURNS int AS $$ SELECT 1; SELECT 2; $$ LANGUAGE sql;"
    found = list(statements(script))
    assert found[0] == "SELECT 'a;b', 'it''s; fine'"
    assert found[1].startswith("CREATE FUNCTION f()") and "SELECT 1; SELECT 2;" in found[1] and len(found) == 2


def test_the_repos_schema_splits_into_whole_statements():
    found = list(statements(SCHEMA.read_text()))
    assert all(stmt.split()[0].upper() in {"CREATE", "ALTER", "DROP", "INSERT", "GRANT", "REVOKE", "SELECT", "COMMENT", "DO"} for stmt in found)
    assert any(stmt.startswith("CREATE OR REPLACE FUNCTION search_articles") and stmt.rstrip().endswith("$$") for stmt in found)
    rebuild = next(stmt for stmt in found if stmt.startswith("CREATE OR REPLACE FUNCTION rebuild_search_suggestions"))
    assert "LOCK TABLE" in rebuild and rebuild.rstrip().endswith("$$")  # a body full of semicolons stays in one piece


def test_a_signed_token_verifies_until_it_expires_and_only_with_its_own_secret(monkeypatch):
    token = gateway.sign({"sub": "u1", "exp": int(time.time()) + 60})
    assert gateway.verify(token)["sub"] == "u1"
    assert gateway.verify(gateway.sign({"sub": "u1", "exp": int(time.time()) - 1})) is None
    monkeypatch.setattr(gateway, "JWT_SECRET", "another-secret-of-at-least-32-characters!!")
    assert gateway.verify(token) is None


def test_a_tampered_token_is_rejected():
    head, body, sig = gateway.sign({"sub": "u1", "exp": int(time.time()) + 60}).split(".")
    forged = gateway.b64(b'{"sub": "u2", "exp": 9999999999}')
    assert gateway.verify(f"{head}.{forged}.{sig}") is None
    assert gateway.verify("not-a-token") is None


def test_passwords_are_salted_and_only_the_right_one_matches():
    stored = gateway.hash_password("secret123")
    assert gateway.password_matches("secret123", stored)
    assert not gateway.password_matches("secret124", stored)
    assert gateway.hash_password("secret123") != stored


def test_storage_removes_the_named_objects_and_skips_missing_ones(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    monkeypatch.setattr(gateway, "STORAGE_DIR", tmp_path)
    (tmp_path / "articles" / "a").mkdir(parents=True)
    (tmp_path / "articles" / "a" / "old.json").write_text("{}")
    (tmp_path / "articles" / "a" / "keep.json").write_text("{}")

    response = TestClient(gateway.app).request(
        "DELETE", "/storage/v1/object/articles", json={"prefixes": ["a/old.json", "a/missing.json"]})

    assert response.json() == [{"name": "a/old.json", "bucket_id": "articles"}]
    assert sorted(f.name for f in (tmp_path / "articles" / "a").iterdir()) == ["keep.json"]


def test_storage_refuses_a_path_outside_its_directory(tmp_path, monkeypatch):
    import pytest
    from fastapi.testclient import TestClient
    monkeypatch.setattr(gateway, "STORAGE_DIR", tmp_path)

    with pytest.raises(ValueError, match="escapes"):
        TestClient(gateway.app).request("DELETE", "/storage/v1/object/articles", json={"prefixes": ["../../etc/passwd"]})
