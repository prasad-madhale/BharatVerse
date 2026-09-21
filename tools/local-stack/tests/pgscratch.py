"""Scratch databases in the stand-in's Postgres for tests: `new_database(schema_sql)` and the helpers around it."""

import os
import sys
from pathlib import Path

import pg8000.native
import pytest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))

from sqlrun import statements  # noqa: E402

SCHEMA = HERE.parents[1] / "backend" / "database" / "schema.sql"
MIGRATION = HERE.parents[1] / "backend" / "database" / "migrations" / "2026-09-search-and-autocomplete.sql"
PORT = 54322 + int(os.environ.get("BV_STACK_OFFSET", "0"))


def connect(database="postgres"):
    return pg8000.native.Connection("postgres", host="127.0.0.1", port=PORT, database=database)


def apply(conn, script):
    for stmt in statements(script):
        conn.run(stmt)


def database_name(conn):
    return conn.run("SELECT current_database()")[0][0]


@pytest.fixture
def new_database():
    """new_database(schema_sql) -> a connection to a fresh database with the auth stand-ins and that schema; dropped afterwards.

    Skips the test when the stand-in's Postgres is not running (start it with tools/local-stack/stack.sh start).
    """
    try:
        admin = connect()
    except Exception:
        pytest.skip(f"no Postgres on 127.0.0.1:{PORT}: start the stand-in with tools/local-stack/stack.sh start")
    made = []

    def make(schema_sql):
        name = f"scratch_{os.getpid()}_{len(made)}"
        admin.run(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
        locale = os.environ.get("BV_TEST_LOCALE")  # e.g. en_US.utf8, the collation Supabase uses (the stand-in's is C.UTF-8)
        admin.run(f"CREATE DATABASE {name}" + (f" TEMPLATE template0 ENCODING 'UTF8' LC_COLLATE '{locale}' LC_CTYPE '{locale}'" if locale else ""))
        conn = connect(name)
        made.append((name, conn))
        # The roles already exist in the cluster; the auth stand-ins and the schema go into the new database
        bootstrap = "\n".join(line for line in (HERE / "bootstrap.sql").read_text().splitlines() if not line.startswith("CREATE ROLE"))
        apply(conn, bootstrap + "\n" + schema_sql)
        return conn

    yield make
    for name, conn in made:
        conn.close()
        admin.run(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
    admin.close()
