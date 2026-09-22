"""
Test support: a real postgrest query builder over a stub HTTP transport.

Tests assert on the request that would be sent to Supabase (path, query string,
headers) instead of on a mock's call list, which cannot catch a wrong operator
name or builder-call order.
"""

import json
from unittest.mock import MagicMock

import httpx
from postgrest import SyncPostgrestClient

BASE_URL = "https://example.supabase.co/rest/v1"
_HEADERS = {"apikey": "test", "Accept": "application/json", "Content-Type": "application/json"}


class WireClient:
    """Just enough of the Supabase client for the services: table(), rpc(), and storage when a blob is given."""

    def __init__(self, handler, blob: bytes | None = None):
        self.requests: list[httpx.Request] = []

        def recording_handler(request: httpx.Request) -> httpx.Response:
            self.requests.append(request)
            return handler(request)

        self._postgrest = SyncPostgrestClient(BASE_URL, headers=_HEADERS)
        self._postgrest.session = httpx.Client(
            base_url=BASE_URL,
            headers=_HEADERS,
            transport=httpx.MockTransport(recording_handler),
        )
        if blob is not None:
            self.storage = MagicMock()
            self.storage.from_.return_value.download.return_value = blob

    def table(self, name: str):
        return self._postgrest.from_(name)

    def rpc(self, name: str, params: dict):
        return self._postgrest.rpc(name, params)


def use_wire(mock_get_supabase, handler, *, admin: bool = False, blob: bytes | None = None) -> WireClient:
    """Make the patched get_supabase() hand its anon (or, with admin=True, admin) client to a WireClient."""
    wire = WireClient(handler, blob)
    supabase = mock_get_supabase.return_value
    (supabase.get_admin_client if admin else supabase.get_client).return_value = wire
    return wire


def article_row(article_id: str = "art_20260703_001", title: str = "The Mauryan Empire") -> dict:
    """A row of the `articles` table."""
    return {
        "id": article_id,
        "title": title,
        "summary": "A summary.",
        "date": "2026-07-03",
        "reading_time_minutes": 13,
        "author": "BharatVerse AI",
        "tags": ["mauryan-empire"],
        "image_url": None,
        "content_file_path": f"articles/2026-07-03/{article_id}.json",
        "created_at": "2026-07-03T00:00:00Z",
        "updated_at": "2026-07-03T00:00:00Z",
    }


def article_blob() -> bytes:
    """The Storage content file that goes with an article row."""
    return json.dumps({
        "content": "## Origins\n\nSome content.",
        "sections": [{"heading": "Origins", "content": "Some content.", "order": 1}],
        "citations": [],
    }).encode("utf-8")


def reply(status: int = 200, payload=None, headers: dict | None = None):
    """A handler that answers every request with this status, JSON body and headers."""
    return lambda request: httpx.Response(status, json=payload, headers=headers)


def rows(*payload):
    """A handler that answers every request with 200 and these rows."""
    return reply(200, list(payload))
