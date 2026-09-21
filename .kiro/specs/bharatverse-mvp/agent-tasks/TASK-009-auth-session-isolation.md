---
id: TASK-009
title: Stop sign-in and sign-up leaking a user's session into the shared client
depends_on: 
requires: py:supabase, py:gotrue
allowed: backend/database/supabase_client.py, backend/services/auth_service.py, backend/tests/test_services/test_auth_service.py, backend/tests/test_auth_session_isolation.py
verify: cd "$BV_ROOT/backend" && python -m pytest tests/test_auth_session_isolation.py tests/test_services/test_auth_service.py -q --no-cov -p no:cacheprovider
verify: cd "$BV_ROOT/backend" && python -m pytest -m "not integration" -q -p no:cacheprovider
verify: cd "$BV_ROOT" && python -m autopep8 --recursive --aggressive --aggressive --max-line-length=127 --exit-code --diff backend/ scrapper/ common/
verify: cd "$BV_ROOT" && python -m flake8 . --count --select=E9,F63,F7,F82 --exclude=.venv,.agent,.git,__pycache__,bharatverse_app,scripts
verify: cd "$BV_ROOT" && ! grep -q 'get_supabase().get_client()' backend/services/auth_service.py
verify: cd "$BV_ROOT" && grep -q 'def create_auth_client' backend/database/supabase_client.py
verify: cd "$BV_ROOT" && grep -q 'auto_refresh_token=False' backend/database/supabase_client.py
commit: fix: sign-in and sign-up no longer leak a user's session into the shared client
---

# TASK-009: Stop sign-in and sign-up leaking a user's session into the shared client

## Why

The backend keeps one shared anonymous Supabase client, from `get_supabase().get_client()`, and uses it for public
reads: articles, search, storage downloads. `AuthService.sign_up` and `sign_in` also ran on that same client.

supabase-py stores a user's session on the client that signed them in, and from then on sends that user's token with
every request the client makes. This was confirmed offline: after one sign-in the shared client's `Authorization`
header changed from the anon key to the user's token. Every later request through it, for any caller, then ran as
that user. Two consequences follow. Reads start failing once that token expires or is revoked. And any read added
later that relies on row-level security, for example a user's own likes, would answer as the last user to sign in.

The fix gives sign-in and sign-up a throwaway client, so the shared client is never signed in. The throwaway client
must have auto-refresh turned off. Otherwise supabase-py starts a timer thread after each sign-in that keeps the
client alive and refreshes its session forever, which leaks one thread and one client per login. That was also
confirmed offline: five logins left five live timer threads.

## Read first, and nothing else

- `backend/database/supabase_client.py`, only the imports and the `get_admin_client` method and the one after it
- `backend/services/auth_service.py`

## Steps

### Step 1. Import `ClientOptions`

<!-- step: replace backend/database/supabase_client.py -->
Replace this exact text:

```python
from supabase import create_client, Client
```

with this exact text:

```python
from supabase import create_client, Client, ClientOptions
```

### Step 2. Add a factory for throwaway clients

This inserts `create_auth_client` directly above `test_connection`.

<!-- step: replace backend/database/supabase_client.py -->
Replace this exact text:

```python
    async def test_connection(self) -> bool:
```

with this exact text:

```python
    def create_auth_client(self) -> Client:
        """
        A brand-new anon client, never cached.

        Signing a user in or up stores that user's session on the client that
        made the call, and supabase-py then sends the user's token with every
        later request from that client. Doing that on the shared client from
        get_client() would make every other request run as the last user to
        sign in. Use this for calls that create a session, and discard it.

        Auto-refresh is off because after a sign-in supabase-py otherwise
        starts a timer thread that keeps this client alive, refreshing its
        session forever. One leaked thread and client per login adds up.
        """
        return create_client(
            self.url,
            self.anon_key,
            options=ClientOptions(auto_refresh_token=False, persist_session=False),
        )

    async def test_connection(self) -> bool:
```

### Step 3. Use it for sign-up

<!-- step: replace backend/services/auth_service.py -->
Replace this exact text:

```python
    async def sign_up(self, email: str, password: str) -> AuthResponse:
        client = get_supabase().get_client()
```

with this exact text:

```python
    async def sign_up(self, email: str, password: str) -> AuthResponse:
        # A throwaway client: sign-up stores the new user's session on the client it runs on.
        client = get_supabase().create_auth_client()
```

### Step 4. Use it for sign-in

<!-- step: replace backend/services/auth_service.py -->
Replace this exact text:

```python
    async def sign_in(self, email: str, password: str) -> AuthResponse:
        client = get_supabase().get_client()
```

with this exact text:

```python
    async def sign_in(self, email: str, password: str) -> AuthResponse:
        # A throwaway client: sign-in stores the user's session on the client it runs on.
        client = get_supabase().create_auth_client()
```

### Step 5. Point the existing sign-up and sign-in tests at the new factory

They mocked `get_client()`, which these two methods no longer call. Five lines change and nothing else in the file.
Run this command exactly. It stops with an error if the count is not five:

<!-- step: run -->
```bash
cd "$BV_ROOT" && python -c "from pathlib import Path; p = Path('backend/tests/test_services/test_auth_service.py'); s = p.read_text(); assert s.count('.get_client.return_value') == 5; p.write_text(s.replace('.get_client.return_value', '.create_auth_client.return_value'))"
```

### Step 6. Add the isolation tests

Create `backend/tests/test_auth_session_isolation.py` with exactly this content. These tests use real Supabase
clients and fake only the network call to Supabase Auth, so they fail on the old behaviour. They check two things:
the shared client stays anonymous, and no refresh timer thread is left running.

<!-- step: create backend/tests/test_auth_session_isolation.py -->
```python
"""
Session isolation for the backend's auth calls.

supabase-py stores a user's session on the client that signed them in, and
then sends that user's token with every later request from that client. The
backend keeps one shared anonymous client for public reads, so signing users
in on it would make every later read run as the last user to sign in. These
tests run the real auth service against real clients, with only the network
call to Supabase Auth faked, and check that the shared client is left alone.
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
```

## Verify

Run every `verify:` command from the front matter, from the repository root, and make each one exit 0.
If the formatting check prints a diff, run `python -m autopep8 --in-place --aggressive --aggressive
--max-line-length=127 <each file you changed>` and run the check again. Do not edit any file that is not listed
under `allowed`.

## Definition of done

- Every step above was applied exactly as written.
- Every `verify:` command exits 0.
- Only files listed under `allowed` changed.
- You did not run git commit, checkout, reset, or push. The runner commits.

## Out of scope

Do not change `sign_out`, `get_current_user`, or any endpoint. Do not change how the shared client or the admin client
is built. Do not touch the mobile app, which signs users in through the Supabase SDK directly.
