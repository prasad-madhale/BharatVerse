"""
The search suggestions in backend/database/schema.sql, run on a real Postgres and checked against a Python model.

Needs the stand-in's Postgres running (`stack.sh start`; BV_STACK_OFFSET picks another stack) and is skipped without it.
It creates and drops a database of its own, so no stack data is touched. BV_PROP_EXAMPLES sets how many random cases run.
"""

import hashlib
import json
import os
import re
import sys
import threading
from pathlib import Path

import pg8000.native
import pytest
from hypothesis import HealthCheck, example, given, settings, strategies as st

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlrun import statements  # noqa: E402

HERE = Path(__file__).resolve().parents[1]
SCHEMA = HERE.parents[1] / "backend" / "database" / "schema.sql"
PORT = 54322 + int(os.environ.get("BV_STACK_OFFSET", "0"))
EXAMPLES = int(os.environ.get("BV_PROP_EXAMPLES", "60"))
INSERT = ("INSERT INTO articles (id, title, summary, date, reading_time_minutes, author, tags, content_file_path) "
          "VALUES (:i, :t, 's', '2026-01-01', 5, 'x', CAST(:g AS jsonb), 'p')")


def connect(database):
    return pg8000.native.Connection("postgres", host="127.0.0.1", port=PORT, database=database)


@pytest.fixture(scope="module")
def db():
    try:
        admin = connect("postgres")
    except Exception:
        pytest.skip(f"no Postgres on 127.0.0.1:{PORT}: start the stand-in with tools/local-stack/stack.sh start")
    name = f"suggestions_test_{os.getpid()}"
    admin.run(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
    admin.run(f"CREATE DATABASE {name}")
    conn = connect(name)
    # The roles already exist in the cluster; the auth stand-ins and the schema go into the new database
    bootstrap = "\n".join(line for line in (HERE / "bootstrap.sql").read_text().splitlines() if not line.startswith("CREATE ROLE"))
    for stmt in statements(bootstrap + "\n" + SCHEMA.read_text()):
        conn.run(stmt)
    yield conn
    conn.close()
    admin.run(f"DROP DATABASE {name} WITH (FORCE)")
    admin.close()


def replace_articles(conn, articles):
    conn.run("DELETE FROM articles")
    for idx, (title, tags) in enumerate(articles):
        conn.run(INSERT, i=f"a{idx}", t=title, g=json.dumps(tags))


# ---- a model of what the SQL should do ------------------------------------------------------------------------

def initcap(text):
    return re.sub(r"[^\W_]+|_", lambda m: m.group(0) if m.group(0) == "_" else m.group(0)[:1].upper() + m.group(0)[1:].lower(), text)


def squash(text):
    return " ".join(text.split())


def suggestions(articles):
    """search_suggestions as {term_key: (term, category, article_count)}."""
    groups = {}
    for idx, (title, tags) in enumerate(articles):
        found = []
        if isinstance(tags, list):
            found += [(initcap(tag.replace("-", " ")), "tag") for tag in tags if isinstance(tag, str)]
        parts = re.split(r"\s*[:–—]+\s*|\s+-\s+", title)
        found += [(part, "title") for part in parts]
        found += [(re.sub(r"^(the|a|an)\s+", "", part, flags=re.I), "title") for part in parts]
        for phrase, category in found:
            phrase = squash(phrase)
            if phrase:
                group = groups.setdefault(phrase.lower(), {"ids": set(), "category": category, "phrases": []})
                group["ids"].add(idx)
                group["category"] = min(group["category"], category)
                group["phrases"].append(phrase)
    return {key: (min(g["phrases"], key=lambda p: (p == p.upper(), p == p.lower(), p)), g["category"], len(g["ids"]))
            for key, g in groups.items()}


def lookup(table, prefix, limit):
    typed = squash(prefix).lower()
    if not typed:
        return []
    hits = [(key, value) for key, value in table.items() if key.startswith(typed)]
    hits.sort(key=lambda kv: (-kv[1][2], kv[1][1] == "title", len(kv[1][0]), kv[0]))
    return [value[0] for _, value in hits][:min(max(10 if limit is None else limit, 0), 20)]


# ---- what to try ----------------------------------------------------------------------------------------------

WORDS = ["Maurya", "MauRya", "maurya", "MAURYA", "Empire", "empire", "Ancient", "India", "Gupta", "Ünder", "é", "1857", "O'Brien",
         "50%", "a_b", "The", "the", "A", "An", "an", "Of", "History"]
GAPS = [" ", "  ", "\t", ": ", ":", " – ", "—", " - ", " -- ", "-"]
SLUGS = ["maurya", "maurya-empire", "ancient-india", "gupta-empire", "empire", "-maurya-", "maurya--empire", "1857-revolt", "a_b",
         "50%", "The-Empire", "MAURYA", "", "-", "ancient--", "Maurya-Empire", "the-maurya", "a-history"]
TIES = ["Maurya", "MauRya", "mAUrya", "Maurya Empire", "Mauryan", "Mauryan Art", "Maurya  Empire", "MAURYA ART", "The Maurya",
        "A Maurya", "An Maurya", "an maurya", "Maurya - Art", "Maurya: Art", "Maurya – Art", "Maurya—Art"]
TIE_PREFIXES = ["m", "ma", "maur", "maurya", "maurya ", "maurya e", "maurya   e", "the m", "an m", "a m", "MAUR", "  Ma", "maurya a"]
WILDCARDS = ["%", "_", "a_", "5%", "\\", "m%", "_a", "%a", "ma%", "50%", "a_b", "a_b ", "'", '"', "-", "- ", "a-"]
# (tags on one article, match_limit): around the default of 10 and the cap of 20
MANY = [(0, None), (1, 5), (9, None), (10, None), (11, None), (12, None), (11, 11), (20, 20), (21, 21), (25, 30), (30, 21),
        (30, None), (25, 20), (25, 0), (25, 500), (25, -1), (5, -2)]
CHARS = st.sampled_from(list("abcdeMNOPéü0123  -'%_\\\".:"))


@st.composite
def titles(draw):
    words = draw(st.lists(st.sampled_from(WORDS), min_size=1, max_size=4))
    gaps = draw(st.lists(st.sampled_from(GAPS), min_size=len(words), max_size=len(words)))
    return "".join(word + gap for word, gap in zip(words[:-1], gaps)) + words[-1]


tag_lists = st.lists(st.one_of(st.sampled_from(SLUGS), st.text(st.sampled_from(list("abcM01-")), max_size=8),
                               st.sampled_from([1, None, True, {"k": "v"}, ["x"]])), max_size=4)
odd_tags = st.sampled_from([{"a": 1}, "just-a-string", 42, None])  # a `tags` that is not an array at all
wide = st.lists(st.tuples(st.one_of(titles(), st.text(CHARS, min_size=1, max_size=10)),
                          st.one_of(tag_lists, tag_lists, tag_lists, odd_tags)), max_size=6)
collisions = st.lists(st.tuples(st.sampled_from(["Maurya", "maurya", "Maurya Empire", "Mauryan", "The Maurya: Empire"]),
                                st.lists(st.sampled_from(["maurya", "MAURYA", "maurya-empire", "Maurya"]), max_size=4)),
                      min_size=1, max_size=5)
limits = st.one_of(st.none(), st.integers(min_value=-2, max_value=30))


@st.composite
def cases(draw):
    """(articles, prefix, limit, edits, deleted): a corpus, a lookup, then edits and a delete the suggestions must follow."""
    if draw(st.integers(0, 9)) < 4:
        kind = draw(st.sampled_from(["ties", "many", "many", "wild"]))
        if kind == "ties":
            return draw(st.lists(st.tuples(st.sampled_from(TIES), st.just([])), min_size=2, max_size=6)), \
                draw(st.sampled_from(TIE_PREFIXES)), draw(limits), [], None
        if kind == "many":
            count, limit = draw(st.sampled_from(MANY))
            return [("Many Tags", [f"t-{k:02d}" for k in range(count)])], draw(st.sampled_from(["t", "T", "t ", "t 0", "t  2"])), limit, [], None
        return draw(wide), draw(st.sampled_from(WILDCARDS)), draw(limits), [], None
    articles = draw(st.one_of(wide, collisions))
    terms = [value[0] for value in suggestions(articles).values()]
    if terms and draw(st.integers(0, 9)) < 8:
        base = draw(st.sampled_from(terms))
        prefix = base[:draw(st.integers(0, min(len(base), 3) if draw(st.booleans()) else len(base)))]
        prefix = draw(st.sampled_from([prefix, prefix.lower(), prefix.upper(), "  " + prefix, prefix + "  ", prefix.replace(" ", "   ")]))
    else:
        prefix = draw(st.text(CHARS, max_size=6))
    edits = draw(st.lists(st.tuples(st.integers(0, max(len(articles) - 1, 0)), st.one_of(titles(), st.just("Renamed")), tag_lists),
                          max_size=2)) if articles else []
    deleted = draw(st.one_of(st.none(), st.integers(0, len(articles) - 1))) if articles else None
    return articles, prefix, draw(limits), edits, deleted


def explicit_cases():
    yield from (([("Many Tags", [f"t-{k:02d}" for k in range(count)])], "t", limit, [], None) for count, limit in MANY)
    yield from (([(title, []) for title in TIES], prefix, limit, [], None) for prefix in TIE_PREFIXES for limit in (None, 2))
    yield from (([(w, [slug]) for w, slug in zip(WORDS, SLUGS)], prefix, None, [], None) for prefix in WILDCARDS)
    yield from (([("An Maurya", []), ("The Gupta", []), ("A Chola", []), ("an Empire: the Sea", ["a-history"])], prefix, None, [], None)
                for prefix in ("maur", "gupt", "chol", "the", "an", "a", "empire", "sea", "history", "the s", "a h"))
    yield ([("Maurya", ["maurya-empire"]), ("Maurya Empire", ["maurya-empire", "MAURYA-EMPIRE"])], "  MAURYA   emp ", None,
           [(0, "Mauryan Art", ["ancient-india"])], 1)


def with_explicit(test):
    for case in explicit_cases():
        test = example(case)(test)
    return test


@with_explicit
@settings(max_examples=EXAMPLES, deadline=None, suppress_health_check=list(HealthCheck))
@given(cases())
def test_the_suggestions_and_the_lookup_follow_the_articles_as_the_model_says(db, case):
    articles, prefix, limit, edits, deleted = case
    replace_articles(db, articles)
    articles = list(articles)
    for idx, title, tags in edits:
        db.run("UPDATE articles SET title = :t, tags = CAST(:g AS jsonb) WHERE id = :i", i=f"a{idx}", t=title, g=json.dumps(tags))
        articles[idx] = (title, tags)
    if deleted is not None:
        db.run("DELETE FROM articles WHERE id = :i", i=f"a{deleted}")
        del articles[deleted]

    want = suggestions(articles)
    got = {row[0]: (row[1], row[2], row[3]) for row in db.run("SELECT term_key, term, category, article_count FROM search_suggestions")}
    assert got == want, f"\n articles={articles!r}\n sql  ={sorted(got.items())}\n model={sorted(want.items())}"

    found = [row[0] for row in db.run("SELECT term FROM autocomplete_suggestions(:p, :n)", p=prefix, n=limit)]
    assert found == lookup(want, prefix, limit), f"\n articles={articles!r}\n prefix={prefix!r} limit={limit}\n sql  ={found}"
    for term in found:  # a suggestion made of plain words finds an article when it is searched for (numbers tokenize differently)
        if re.fullmatch(r"[^\W\d_]{2,}(?: [^\W\d_]{2,})*", term) and db.run(
                "SELECT numnode(websearch_to_tsquery('english', :t))", t=term)[0][0] > 0:
            assert db.run("SELECT count(*) FROM search_articles(:t, 5)", t=term)[0][0] > 0, f"searching {term!r} finds nothing"


def db_name(conn):
    return conn.run("SELECT current_database()")[0][0]


def test_only_the_trigger_can_write_the_suggestions(db):
    replace_articles(db, [("Zzqsvc Test", ["zzqsvc-tag"])])
    name = db_name(db)

    def attempt(role, sql):
        conn = connect(name)
        try:
            conn.run(f"SET ROLE {role}")
            return conn.run(sql)
        finally:
            conn.close()

    assert attempt("anon", "SELECT term FROM autocomplete_suggestions('zzqsvc')") == [["Zzqsvc Tag"], ["Zzqsvc Test"]]
    for role in ("anon", "authenticated"):
        for sql in ("SELECT rebuild_search_suggestions()", "SELECT refresh_search_suggestions()"):
            with pytest.raises(pg8000.exceptions.DatabaseError, match="permission denied"):
                attempt(role, sql)
    with pytest.raises(pg8000.exceptions.DatabaseError, match="row-level security"):
        attempt("anon", "INSERT INTO search_suggestions VALUES ('x', 'X', 'tag', 1)")
    assert attempt("anon", "WITH d AS (DELETE FROM search_suggestions RETURNING 1) SELECT count(*) FROM d") == [[0]]

    # The service role writes articles without any right to the suggestions or the functions, and the trigger still runs
    attempt("service_role", "INSERT INTO articles (id, title, summary, date, reading_time_minutes, author, tags, content_file_path) "
                            "VALUES ('svc', 'Zzqsvc Written', 's', '2026-01-01', 5, 'x', '[]', 'p')")
    assert db.run("SELECT term FROM autocomplete_suggestions('zzqsvc w')") == [["Zzqsvc Written"]]


def test_writers_at_the_same_time_leave_what_a_rebuild_would(db):
    replace_articles(db, [("Existing", ["zzqconc-shared"])])
    name, errors = db_name(db), []

    def write(n):
        try:
            conn = connect(name)
            conn.run(INSERT, i=f"conc{n}", t=f"Zzqconc {n}", g=json.dumps([f"zzqconc-tag-{n}", "zzqconc-shared"]))
            conn.close()
        except Exception as e:  # noqa: BLE001
            errors.append(repr(e))

    threads = [threading.Thread(target=write, args=(n,)) for n in range(8)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert errors == []

    def table():
        rows = db.run("SELECT term_key, term, category, article_count FROM search_suggestions ORDER BY term_key")
        return hashlib.md5(json.dumps(rows).encode()).hexdigest()

    after_the_writes = table()
    db.run("SELECT rebuild_search_suggestions()")
    assert table() == after_the_writes
    assert db.run("SELECT article_count FROM search_suggestions WHERE term_key = 'zzqconc shared'") == [[9]]
