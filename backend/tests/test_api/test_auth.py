"""
Unit tests for the auth API router.

Uses FastAPI's TestClient with AuthService mocked out -- no live Supabase
or network calls.
"""

from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

from backend.main import app
from backend.models.auth import AuthResponse
from backend.services.auth_service import AuthError


def make_auth_response():
    return AuthResponse(
        access_token="access-token-abc",
        refresh_token="refresh-token-xyz",
        user_id="user-123",
        email="test@example.com",
    )


@pytest.fixture
def client():
    return TestClient(app)


class TestSignUp:
    def test_returns_auth_response_on_success(self, client):
        with patch("backend.api.auth.AuthService") as mock_service_class:
            mock_service_class.return_value.sign_up = AsyncMock(return_value=make_auth_response())

            response = client.post(
                "/api/v1/auth/signup", json={"email": "test@example.com", "password": "s3cret-password"}
            )

        assert response.status_code == 200
        body = response.json()
        assert body["access_token"] == "access-token-abc"
        assert body["user_id"] == "user-123"

    def test_returns_400_on_auth_error(self, client):
        with patch("backend.api.auth.AuthService") as mock_service_class:
            mock_service_class.return_value.sign_up = AsyncMock(
                side_effect=AuthError("User already registered")
            )

            response = client.post(
                "/api/v1/auth/signup", json={"email": "test@example.com", "password": "s3cret-password"}
            )

        assert response.status_code == 400
        assert "already registered" in response.json()["detail"]

    def test_returns_422_for_invalid_email(self, client):
        response = client.post(
            "/api/v1/auth/signup", json={"email": "not-an-email", "password": "s3cret-password"}
        )

        assert response.status_code == 422


class TestLogin:
    def test_returns_auth_response_on_success(self, client):
        with patch("backend.api.auth.AuthService") as mock_service_class:
            mock_service_class.return_value.sign_in = AsyncMock(return_value=make_auth_response())

            response = client.post(
                "/api/v1/auth/login", json={"email": "test@example.com", "password": "s3cret-password"}
            )

        assert response.status_code == 200
        assert response.json()["access_token"] == "access-token-abc"

    def test_returns_401_on_invalid_credentials(self, client):
        with patch("backend.api.auth.AuthService") as mock_service_class:
            mock_service_class.return_value.sign_in = AsyncMock(
                side_effect=AuthError("Invalid login credentials")
            )

            response = client.post(
                "/api/v1/auth/login", json={"email": "test@example.com", "password": "wrong-password"}
            )

        assert response.status_code == 401


class TestLogout:
    def test_returns_204_on_success(self, client):
        with patch("backend.api.auth.AuthService") as mock_service_class:
            mock_service_class.return_value.sign_out = AsyncMock(return_value=None)

            response = client.post(
                "/api/v1/auth/logout", headers={"Authorization": "Bearer valid-token-abc"}
            )

        assert response.status_code == 204
        mock_service_class.return_value.sign_out.assert_called_once_with("valid-token-abc")

    def test_returns_403_without_authorization_header(self, client):
        # HTTPBearer's own default for a missing header is 403, not 401 --
        # a FastAPI/Starlette quirk, verified rather than assumed.
        response = client.post("/api/v1/auth/logout")

        assert response.status_code == 403

    def test_returns_400_on_auth_error(self, client):
        with patch("backend.api.auth.AuthService") as mock_service_class:
            mock_service_class.return_value.sign_out = AsyncMock(
                side_effect=AuthError("Invalid token")
            )

            response = client.post(
                "/api/v1/auth/logout", headers={"Authorization": "Bearer garbage-token"}
            )

        assert response.status_code == 400
