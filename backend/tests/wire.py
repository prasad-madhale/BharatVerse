"""
Test support: a real postgrest query builder wired to a stub HTTP transport.

Mocking `client.table(...).select(...)` proves a call happened, not what
would actually be sent to Supabase. A wrong operator name or option value
passes a mock-based test and still fails in production. This helper runs
the real service code against a real query builder and records the HTTP
request that would have gone out, so a test can assert on the real path and
query string.
"""

import httpx
from postgrest import SyncPostgrestClient

BASE_URL = "https://example.supabase.co/rest/v1"
_HEADERS = {"apikey": "test", "Accept": "application/json", "Content-Type": "application/json"}


class WireClient:
    """Just enough of the Supabase client surface for the services: table()."""

    def __init__(self, handler):
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

    def table(self, name: str):
        return self._postgrest.from_(name)
