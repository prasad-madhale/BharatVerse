"""
Unit tests for AuthService.

Tests sign-up/sign-in/sign-out logic with a mocked Supabase client (no live
network calls) -- same conventions as test_article_service.py.
"""

from unittest.mock import MagicMock, patch

import pytest
from gotrue.errors import AuthApiError

from backend.services.auth_service import AuthError, AuthService


def make_auth_response(user_id="user-123", email="test@example.com"):
    session = MagicMock(access_token="access-token-abc", refresh_token="refresh-token-xyz")
    user = MagicMock(id=user_id, email=email)
    return MagicMock(session=session, user=user)


@pytest.fixture
def mock_supabase_client():
    return MagicMock()


class TestSignUp:
    @pytest.mark.asyncio
    @patch("backend.services.auth_service.get_supabase")
    async def test_returns_auth_response_on_success(self, mock_get_supabase, mock_supabase_client):
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        mock_supabase_client.auth.sign_up.return_value = make_auth_response()

        result = await AuthService().sign_up("test@example.com", "s3cret-password")

        assert result.access_token == "access-token-abc"
        assert result.refresh_token == "refresh-token-xyz"
        assert result.user_id == "user-123"
        assert result.email == "test@example.com"
        mock_supabase_client.auth.sign_up.assert_called_once_with(
            {"email": "test@example.com", "password": "s3cret-password"}
        )

    @pytest.mark.asyncio
    @patch("backend.services.auth_service.get_supabase")
    async def test_raises_auth_error_on_api_error(self, mock_get_supabase, mock_supabase_client):
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        mock_supabase_client.auth.sign_up.side_effect = AuthApiError(
            "User already registered", 400, "user_already_exists"
        )

        with pytest.raises(AuthError, match="already registered"):
            await AuthService().sign_up("test@example.com", "s3cret-password")

    @pytest.mark.asyncio
    @patch("backend.services.auth_service.get_supabase")
    async def test_raises_auth_error_when_no_session_returned(self, mock_get_supabase, mock_supabase_client):
        # Supabase returns a user but no session when email confirmation is required.
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        mock_supabase_client.auth.sign_up.return_value = MagicMock(session=None, user=MagicMock())

        with pytest.raises(AuthError, match="email confirmation"):
            await AuthService().sign_up("test@example.com", "s3cret-password")


class TestSignIn:
    @pytest.mark.asyncio
    @patch("backend.services.auth_service.get_supabase")
    async def test_returns_auth_response_on_success(self, mock_get_supabase, mock_supabase_client):
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        mock_supabase_client.auth.sign_in_with_password.return_value = make_auth_response()

        result = await AuthService().sign_in("test@example.com", "s3cret-password")

        assert result.access_token == "access-token-abc"
        mock_supabase_client.auth.sign_in_with_password.assert_called_once_with(
            {"email": "test@example.com", "password": "s3cret-password"}
        )

    @pytest.mark.asyncio
    @patch("backend.services.auth_service.get_supabase")
    async def test_raises_auth_error_on_invalid_credentials(self, mock_get_supabase, mock_supabase_client):
        mock_get_supabase.return_value.get_client.return_value = mock_supabase_client
        mock_supabase_client.auth.sign_in_with_password.side_effect = AuthApiError(
            "Invalid login credentials", 400, "invalid_credentials"
        )

        with pytest.raises(AuthError, match="Invalid login credentials"):
            await AuthService().sign_in("test@example.com", "wrong-password")


class TestSignOut:
    @pytest.mark.asyncio
    @patch("backend.services.auth_service.get_supabase")
    async def test_revokes_session_via_admin_api(self, mock_get_supabase, mock_supabase_client):
        mock_get_supabase.return_value.get_admin_client.return_value = mock_supabase_client

        await AuthService().sign_out("access-token-abc")

        mock_supabase_client.auth.admin.sign_out.assert_called_once_with("access-token-abc")

    @pytest.mark.asyncio
    @patch("backend.services.auth_service.get_supabase")
    async def test_raises_auth_error_on_api_error(self, mock_get_supabase, mock_supabase_client):
        mock_get_supabase.return_value.get_admin_client.return_value = mock_supabase_client
        mock_supabase_client.auth.admin.sign_out.side_effect = AuthApiError(
            "Invalid token", 401, "bad_jwt"
        )

        with pytest.raises(AuthError, match="Invalid token"):
            await AuthService().sign_out("garbage-token")
