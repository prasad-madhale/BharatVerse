"""
Unit tests for get_current_user (backend/api/deps.py).

Calls the dependency function directly with a fake HTTPAuthorizationCredentials
object -- no real FastAPI request/route needed, and no live network calls.
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from gotrue.errors import AuthApiError

from backend.api.deps import get_current_user


def make_credentials(token="valid-token-abc"):
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


class TestGetCurrentUser:
    @pytest.mark.asyncio
    @patch("backend.api.deps.get_supabase")
    async def test_returns_user_for_valid_token(self, mock_get_supabase):
        mock_client = MagicMock()
        mock_user = MagicMock(id="user-123", email="test@example.com")
        mock_client.auth.get_user.return_value = MagicMock(user=mock_user)
        mock_get_supabase.return_value.get_client.return_value = mock_client

        result = await get_current_user(make_credentials("valid-token-abc"))

        assert result.id == "user-123"
        mock_client.auth.get_user.assert_called_once_with("valid-token-abc")

    @pytest.mark.asyncio
    @patch("backend.api.deps.get_supabase")
    async def test_raises_401_when_supabase_rejects_token(self, mock_get_supabase):
        mock_client = MagicMock()
        mock_client.auth.get_user.side_effect = AuthApiError("Invalid JWT", 401, "bad_jwt")
        mock_get_supabase.return_value.get_client.return_value = mock_client

        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(make_credentials("garbage-token"))

        assert exc_info.value.status_code == 401

    @pytest.mark.asyncio
    @patch("backend.api.deps.get_supabase")
    async def test_raises_401_when_response_has_no_user(self, mock_get_supabase):
        mock_client = MagicMock()
        mock_client.auth.get_user.return_value = MagicMock(user=None)
        mock_get_supabase.return_value.get_client.return_value = mock_client

        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(make_credentials("expired-token"))

        assert exc_info.value.status_code == 401

    @pytest.mark.asyncio
    @patch("backend.api.deps.get_supabase")
    async def test_raises_401_when_response_is_none(self, mock_get_supabase):
        mock_client = MagicMock()
        mock_client.auth.get_user.return_value = None
        mock_get_supabase.return_value.get_client.return_value = mock_client

        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(make_credentials("weird-token"))

        assert exc_info.value.status_code == 401
