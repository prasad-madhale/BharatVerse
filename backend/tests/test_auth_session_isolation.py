"""
Session isolation for the backend's auth calls.

supabase-py stores a session on the client that signed in, so signing users in on the shared anonymous client
would make later public reads run as that user. Real clients are used; only the HTTP call to Supabase Auth is faked.
"""

import threading
import time
from unittest.mock import patch

import pytest
from gotrue._sync.gotrue_client import SyncGoTrueClient

from backend.database import get_supabase
from backend.services.auth_service import AuthService

ANON_KEY = "anon.public.key"
USER_TOKEN = "user.session.token"


def fake_auth_response():
    return {
        "access_token": USER_TOKEN,
        "token_type": "bearer",
        "expires_in": 3600,
        "expires_at": int(time.time()) + 3600,
        "refresh_token": "refresh-token",
        "user": {
            "id": "11111111-1111-1111-1111-111111111111",
            "aud": "authenticated",
            "app_metadata": {},
            "user_metadata": {},
            "created_at": "2026-01-01T00:00:00Z",
            "email": "alice@example.com",
        },
    }


@pytest.fixture
def fake_supabase_auth(monkeypatch):
    """Real Supabase clients, with only the HTTP call to Supabase Auth faked."""
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", ANON_KEY)
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "service.role.key")

    def fake_request(self, method, path, *, xform=None, **kwargs):
        return xform(fake_auth_response())

    with patch.object(SyncGoTrueClient, "_request", fake_request):
        yield


def shared_client_headers():
    shared = get_supabase().get_client()
    return shared.options.headers["Authorization"], shared.postgrest.session.headers["Authorization"]


class TestSharedClientStaysAnonymous:
    @pytest.mark.asyncio
    async def test_sign_in_returns_the_session_but_does_not_leak_it(self, fake_supabase_auth):
        response = await AuthService().sign_in("alice@example.com", "password")

        assert response.access_token == USER_TOKEN
        assert shared_client_headers() == (f"Bearer {ANON_KEY}", f"Bearer {ANON_KEY}")

    @pytest.mark.asyncio
    async def test_sign_up_returns_the_session_but_does_not_leak_it(self, fake_supabase_auth):
        response = await AuthService().sign_up("alice@example.com", "password")

        assert response.access_token == USER_TOKEN
        assert shared_client_headers() == (f"Bearer {ANON_KEY}", f"Bearer {ANON_KEY}")


def refresh_timers():
    return [t for t in threading.enumerate() if isinstance(t, threading.Timer)]


class TestNoBackgroundRefreshTimer:
    @pytest.mark.asyncio
    async def test_sign_in_leaves_no_refresh_timer_running(self, fake_supabase_auth):
        before = len(refresh_timers())

        await AuthService().sign_in("alice@example.com", "password")

        assert len(refresh_timers()) == before

    @pytest.mark.asyncio
    async def test_sign_up_leaves_no_refresh_timer_running(self, fake_supabase_auth):
        before = len(refresh_timers())

        await AuthService().sign_up("alice@example.com", "password")

        assert len(refresh_timers()) == before


class TestCreateAuthClient:
    @patch("backend.database.supabase_client.create_client")
    def test_returns_a_new_client_each_time_and_never_caches_it(self, mock_create_client, fake_supabase_auth):
        mock_create_client.side_effect = lambda url, key, options=None: object()
        supabase = get_supabase()

        first, second = supabase.create_auth_client(), supabase.create_auth_client()

        assert first is not second
        assert supabase._client is None
        assert mock_create_client.call_args_list[0].args == ("https://example.supabase.co", ANON_KEY)

    @patch("backend.database.supabase_client.create_client")
    def test_disables_auto_refresh_and_session_persistence(self, mock_create_client, fake_supabase_auth):
        mock_create_client.side_effect = lambda url, key, options=None: object()

        get_supabase().create_auth_client()

        options = mock_create_client.call_args.kwargs["options"]
        assert options.auto_refresh_token is False
        assert options.persist_session is False
