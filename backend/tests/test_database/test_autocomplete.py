"""
Integration test for search suggestions against the database in .env (or BV_ENV_FILE).

Inserts articles whose phrases start with invented words, so nothing already published can match, and deletes them.
"""

import pytest

from backend.database import get_supabase
from backend.services.search_service import SearchService

IDS = [f"art_test_ac_{n}" for n in range(1, 12)]


def article(article_id: str, title: str, tags: list[str]) -> dict:
    return {
        "id": article_id,
        "title": title,
        "summary": "A temporary article for the autocomplete test.",
        "date": "2026-02-15",
        "reading_time_minutes": 5,
        "author": "BharatVerse AI",
        "tags": tags,
        "content_file_path": f"articles/2026-02-15/{article_id}.json",
    }


@pytest.mark.asyncio
@pytest.mark.integration
async def test_suggestions_are_the_titles_and_tags_that_start_with_what_was_typed():
    client = get_supabase().get_admin_client()
    suggest = SearchService().autocomplete
    try:
        client.table("articles").insert([
            article(IDS[0], "Zzqac Empire: Zzqbc Subtitle", ["zzqac-empire", "zzqac-india"]),
            # The same phrase twice on one article counts once
            article(IDS[1], "Zzqac Dynasty", ["zzqac-empire", "ZZQAC-EMPIRE"]),
            article(IDS[2], "The Zzqac Chronicle", ["zzqac-india"]),
            article(IDS[3], "Zzqac  Spaced   Title", []),
            article(IDS[4], "Zzqac Aardvark - Zzqdd Dash", ["zzqac-zebra-crossing-signs"]),
            article(IDS[5], "An Zzqex Anthem: A Zzqfx Tale", []),
            # A phrase that is a title part and a tag counts as a tag, so it ranks with the tags
            article(IDS[6], "Zzqgg Alpha", ["zzqgg-alpha"]),
            article(IDS[7], "Unrelated Title Words", ["zzqgg-beta-gamma-delta"]),
        ]).execute()

        # Phrases more articles carry first, then tags before titles (however long the tag), then shorter ones
        assert await suggest("zzqac") == [
            "Zzqac India", "Zzqac Empire", "Zzqac Zebra Crossing Signs", "Zzqac Dynasty", "Zzqac Aardvark",
            "Zzqac Chronicle", "Zzqac Spaced Title"]
        assert await suggest("zzqac", limit=2) == ["Zzqac India", "Zzqac Empire"]
        assert await suggest("zzqgg") == ["Zzqgg Alpha", "Zzqgg Beta Gamma Delta"]

        # A title is suggested by each of its parts, split at a colon or a dash, and without a leading article
        assert await suggest("zzqbc") == ["Zzqbc Subtitle"]
        assert await suggest("zzqdd") == ["Zzqdd Dash"]
        assert await suggest("zzqac ch") == ["Zzqac Chronicle"]
        assert await suggest("the zzq") == ["The Zzqac Chronicle"]
        assert await suggest("zzqex") == ["Zzqex Anthem"]
        assert await suggest("an zzq") == ["An Zzqex Anthem"]
        assert await suggest("zzqfx") == ["Zzqfx Tale"]
        assert await suggest("a zzq") == ["A Zzqfx Tale"]
        # A spaced hyphen would read as "not" when the suggestion is searched, so none is ever suggested
        assert await suggest("zzqac aardvark -") == []

        # Case and extra whitespace, in what was typed and in a stored title, do not matter
        assert await suggest("  ZZQAC   emp ") == ["Zzqac Empire"]
        assert await suggest("zzqac spaced t") == ["Zzqac Spaced Title"]

        # Only the start of a phrase matches, and LIKE wildcards are just characters
        assert await suggest("chronicle") == []
        assert await suggest("zzq%") == []
        assert await suggest("zzqa_") == []
        assert await suggest("%") == []
        assert await suggest("   ") == []

        # Whatever is suggested finds an article when it is searched for
        for term in await suggest("zzq"):
            assert client.rpc("search_articles", {"search_query": term, "match_limit": 5}).execute().data, term

        # A change to the articles shows at once: nothing has to be kept in step by hand
        client.table("articles").update({"title": "Zzqac Renamed"}).eq("id", IDS[1]).execute()
        assert await suggest("zzqac d") == []
        assert await suggest("zzqac ren") == ["Zzqac Renamed"]
        client.table("articles").delete().eq("id", IDS[0]).execute()
        assert await suggest("zzqbc") == []
        assert await suggest("zzqac") == [
            "Zzqac India", "Zzqac Empire", "Zzqac Zebra Crossing Signs", "Zzqac Renamed", "Zzqac Aardvark",
            "Zzqac Chronicle", "Zzqac Spaced Title"]
    finally:
        client.table("articles").delete().in_("id", IDS).execute()


@pytest.mark.asyncio
@pytest.mark.integration
async def test_the_number_of_suggestions_is_capped_whatever_a_caller_asks_for():
    client = get_supabase().get_admin_client()

    def ask(**params) -> list:
        return client.rpc("autocomplete_suggestions", {"prefix": "zzqlim", **params}).execute().data

    try:
        client.table("articles").insert(article(IDS[7], "Zzqlim", [f"zzqlim-{n:02d}" for n in range(1, 26)])).execute()

        assert len(ask()) == 10
        assert len(ask(match_limit=None)) == 10
        assert len(ask(match_limit=7)) == 7
        assert len(ask(match_limit=500)) == 20
        assert ask(match_limit=0) == []
        assert ask(match_limit=-1) == []
    finally:
        client.table("articles").delete().eq("id", IDS[7]).execute()


@pytest.mark.asyncio
@pytest.mark.integration
async def test_a_suggestion_is_always_something_a_search_finds_and_a_bad_value_cannot_stop_a_save():
    client = get_supabase().get_admin_client()
    suggest = SearchService().autocomplete
    try:
        client.table("articles").insert([
            # A hyphen before a digit is indexed as a space too, so a number-suffixed tag reads as a plain phrase
            article(IDS[8], "Zzqnum Article", ["zzqcovid-19", "zzqworld-war-2"]),
            # A word after a space and a hyphen is read by a search as "not", so nothing is offered for the title
            article(IDS[9], "Zzqnot -Excluded Word", []),
            # Far more than an index row can hold: the save must still work, and nothing is offered
            article(IDS[10], "Zzqlong " + "x" * 3000, ["zzqlong-" + "y" * 3000]),
        ]).execute()

        assert await suggest("zzqcovid") == ["Zzqcovid 19"]
        assert await suggest("zzqworld") == ["Zzqworld War 2"]
        assert await suggest("zzqnot") == []
        assert await suggest("zzqlong") == []
        for term in await suggest("zzqnum") + await suggest("zzqcovid") + await suggest("zzqworld"):
            assert client.rpc("search_articles", {"search_query": term, "match_limit": 5}).execute().data, term
    finally:
        client.table("articles").delete().in_("id", IDS[8:11]).execute()
