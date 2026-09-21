"""
The search suggestions in backend/database/schema.sql, run on a real Postgres and checked against a Python model.
Which phrases a search can find is Postgres's own text search, so the model asks the database that one question.

Needs the stand-in's Postgres running (`stack.sh start`; BV_STACK_OFFSET picks another stack) and is skipped without it.
It creates and drops a database of its own, so no stack data is touched. BV_PROP_EXAMPLES sets how many random cases run.
"""

import hashlib
import json
import os
import re
import threading

import pg8000.exceptions
import pytest
from hypothesis import HealthCheck, example, given, settings, strategies as st

from pgscratch import SCHEMA, connect, database_name

EXAMPLES = int(os.environ.get("BV_PROP_EXAMPLES", "60"))
INSERT = ("INSERT INTO articles (id, title, summary, date, reading_time_minutes, author, tags, content_file_path) "
          "VALUES (:i, :t, 's', '2026-01-01', 5, 'x', CAST(:g AS jsonb), 'p')")


@pytest.fixture
def db(new_database):
    return new_database(SCHEMA.read_text())


def replace_articles(conn, articles):
    conn.run("DELETE FROM articles")
    for idx, (title, tags) in enumerate(articles):
        conn.run(INSERT, i=f"a{idx}", t=title, g=json.dumps(tags))


# ---- a model of what the SQL should do ------------------------------------------------------------------------

def initcap(text):
    return re.sub(r"[^\W_]+|_", lambda m: m.group(0) if m.group(0) == "_" else m.group(0)[:1].upper() + m.group(0)[1:].lower(), text)


def squash(text):
    return " ".join(text.split())


def suggestions(articles, matches):
    """search_suggestions as {term_key: (term, category, article_count)} for [(id, title, tags)].

    matches(id, phrase) says whether searching for the phrase finds that article.
    """
    groups = {}
    for article_id, title, tags in articles:
        found = []
        if isinstance(tags, list):
            for tag in (tag for tag in tags if isinstance(tag, str)):
                spaced = initcap(tag.replace("-", " "))
                found.append((spaced if matches(article_id, spaced) else initcap(tag), "tag"))
        parts = re.split(r"\s*[:\u2013\u2014]+\s*|\s+-\s+", title)
        found += [(part, "title") for part in parts]
        found += [(re.sub(r"^(the|a|an)\s+", "", part, flags=re.I), "title") for part in parts]
        for phrase, category in found:
            phrase = squash(phrase)
            if phrase and len(phrase) <= 200 and matches(article_id, phrase):
                group = groups.setdefault(phrase.lower(), {"ids": set(), "category": category, "phrases": []})
                group["ids"].add(article_id)
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
    candidates = suggestions([(f"a{n}", title, tags) for n, (title, tags) in enumerate(articles)], lambda *_: True)
    terms = [value[0] for value in candidates.values()]
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


SEARCHY = [("The Revolt: Uprising of 1857", ["revolt-1857", "covid-19", "world-war-2", "medieval-india"]),
           ("Ashoka -Kalinga Aftermath", []), ("Sher Shah Suri --- Road Builder", ["sher-shah"]), ("The", []),
           ('The "Iron" Pillar of Delhi', ["iron-pillar", "rise-or-fall"]), ("Rise or Fall of Empires", [])]


def explicit_cases():
    yield from ((SEARCHY, prefix, None, [], None) for prefix in ("co", "rev", "world", "ash", "sher", "the", "iron", "rise", "up", "a"))
    yield (SEARCHY, "co", None, [(1, "Covid Kalinga Aftermath", ["covid-19"])], 0)
    poison = [("x" * 3000, ["y" * 3000]), ("Long title " + "word " * 80 + "end", ["-".join(["long"] * 300)]), ("Short", [])]
    yield from ((poison, prefix, None, [], None) for prefix in ("x", "y", "long title word", "long long", "s"))
    yield ([("a " * 150 + "b", [])], "a a a", None, [], None)
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
    live = [(f"a{n}", title, tags) for n, (title, tags) in enumerate(articles) if n != deleted]

    asked = {}

    def matches(article_id, phrase):
        if (article_id, phrase) not in asked:
            asked[article_id, phrase] = db.run(
                "SELECT search_vector @@ websearch_to_tsquery('english', :p) FROM articles WHERE id = :i", p=phrase, i=article_id)[0][0]
        return asked[article_id, phrase]

    want = suggestions(live, matches)
    got = {row[0]: (row[1], row[2], row[3]) for row in db.run("SELECT term_key, term, category, article_count FROM search_suggestions")}
    assert got == want, f"\n articles={live!r}\n sql  ={sorted(got.items())}\n model={sorted(want.items())}"

    found = [row[0] for row in db.run("SELECT term FROM autocomplete_suggestions(:p, :n)", p=prefix, n=limit)]
    assert found == lookup(want, prefix, limit), f"\n articles={live!r}\n prefix={prefix!r} limit={limit}\n sql  ={found}"
    for term in found:  # whatever is suggested finds an article when it is searched for
        assert db.run("SELECT count(*) FROM search_articles(:t, 5)", t=term)[0][0] > 0, f"searching {term!r} finds nothing"


def test_only_the_trigger_writes_suggestions_and_only_the_service_role_writes_articles(db):
    replace_articles(db, [("Zzqsvc Test", ["zzqsvc-tag"])])
    name = database_name(db)

    def attempt(role, sql):
        conn = connect(name)
        try:
            conn.run(f"SET ROLE {role}")
            return conn.run(sql)
        finally:
            conn.close()

    def denied(role, sql, what):
        with pytest.raises(pg8000.exceptions.DatabaseError, match=f"permission denied for {what}"):
            attempt(role, sql)

    write = ("INSERT INTO articles (id, title, summary, date, reading_time_minutes, author, tags, content_file_path) "
             "VALUES ('h', 'h', 'h', '2026-01-01', 1, 'x', '[]', 'p')")
    assert attempt("anon", "SELECT term FROM autocomplete_suggestions('zzqsvc')") == [["Zzqsvc Tag"], ["Zzqsvc Test"]]
    assert db.run("SELECT relrowsecurity FROM pg_class WHERE relname = 'search_suggestions'") == [[True]]
    for role in ("anon", "authenticated"):
        denied(role, "SELECT rebuild_search_suggestions()", "function")
        denied(role, "SELECT refresh_search_suggestions()", "function")
        # A refused write must fail at once, not run a statement whose trigger then rebuilds everything
        denied(role, write, "table articles")
        denied(role, "UPDATE articles SET title = 'x'", "table articles")
        denied(role, "DELETE FROM articles WHERE id = 'nope'", "table articles")
        denied(role, "INSERT INTO search_suggestions VALUES ('x', 'X', 'tag', 1)", "table search_suggestions")
        denied(role, "DELETE FROM search_suggestions", "table search_suggestions")
        denied(role, "TRUNCATE articles", "table articles")
        denied(role, "TRUNCATE search_suggestions", "table search_suggestions")
    denied("service_role", "DELETE FROM search_suggestions", "table search_suggestions")
    denied("service_role", "TRUNCATE search_suggestions", "table search_suggestions")

    # The service role writes articles without any right to the suggestions or the functions, and the trigger still runs
    attempt("service_role", write.replace("'h', 'h', 'h'", "'svc', 'Zzqsvc Written', 's'"))
    assert db.run("SELECT term FROM autocomplete_suggestions('zzqsvc w')") == [["Zzqsvc Written"]]


def test_a_broken_suggestions_table_never_stops_an_article_being_written(db):
    replace_articles(db, [("Existing", [])])
    db.run("ALTER TABLE search_suggestions RENAME TO search_suggestions_held")
    try:
        db.run(INSERT, i="written", t="Zzqbroken Written", g="[]")  # a rebuild against a missing table fails: the write must not
        assert db.run("SELECT title FROM articles WHERE id = 'written'") == [["Zzqbroken Written"]]
        assert any("search_suggestions not rebuilt" in str(notice) for notice in db.notices)
    finally:
        db.run("ALTER TABLE search_suggestions_held RENAME TO search_suggestions")
    db.run("SELECT rebuild_search_suggestions()")
    assert db.run("SELECT term FROM autocomplete_suggestions('zzqbroken')") == [["Zzqbroken Written"]]


def test_a_half_applied_migration_leaves_publishing_working(db):
    """The earlier table still there when the trigger arrives (the new table's statements skipped) breaks the rebuild, not the write."""
    replace_articles(db, [("Existing", [])])
    db.run("ALTER TABLE search_suggestions RENAME TO search_suggestions_held")
    try:
        db.run("CREATE TABLE search_suggestions (id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), term TEXT NOT NULL, "
               "category TEXT NOT NULL, frequency INTEGER DEFAULT 1, article_count INTEGER DEFAULT 0)")
        db.run("INSERT INTO articles (id, title, summary, date, reading_time_minutes, author, tags, content_file_path) "
               "VALUES ('up', 'Zzqhalf', 's', '2026-01-01', 5, 'x', '[]', 'p') "
               "ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title")  # what the pipeline sends
        assert db.run("SELECT title FROM articles WHERE id = 'up'") == [["Zzqhalf"]]
    finally:
        db.run("DROP TABLE search_suggestions")
        db.run("ALTER TABLE search_suggestions_held RENAME TO search_suggestions")
    db.run("SELECT rebuild_search_suggestions()")


def test_writers_at_the_same_time_leave_what_a_rebuild_would(db):
    replace_articles(db, [("Existing", ["zzqconc-shared"])])
    name, errors = database_name(db), []

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
