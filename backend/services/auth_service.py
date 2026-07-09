"""
Auth operations backed by Supabase Auth -- no password hashing or JWT
issuance here, that's entirely Supabase's responsibility. This is a thin
wrapper so backend/api/auth.py doesn't call the Supabase SDK directly.
"""

import logging

from gotrue.errors import AuthApiError

from backend.database import get_supabase
from backend.models.auth import AuthResponse

logger = logging.getLogger(__name__)


class AuthError(Exception):
    """Raised when a sign-up/sign-in/sign-out call fails."""


class AuthService:
    """Thin wrapper over Supabase Auth's email/password flows."""

    async def sign_up(self, email: str, password: str) -> AuthResponse:
        client = get_supabase().get_client()
        try:
            response = client.auth.sign_up({"email": email, "password": password})
        except AuthApiError as e:
            raise AuthError(str(e)) from e

        if response.session is None or response.user is None:
            raise AuthError("Sign up did not return a session (email confirmation may be required)")

        logger.info(f"Signed up user {response.user.id}")
        return AuthResponse(
            access_token=response.session.access_token,
            refresh_token=response.session.refresh_token,
            user_id=response.user.id,
            email=response.user.email,
        )

    async def sign_in(self, email: str, password: str) -> AuthResponse:
        client = get_supabase().get_client()
        try:
            response = client.auth.sign_in_with_password({"email": email, "password": password})
        except AuthApiError as e:
            raise AuthError(str(e)) from e

        if response.session is None or response.user is None:
            raise AuthError("Sign in did not return a session")

        logger.info(f"Signed in user {response.user.id}")
        return AuthResponse(
            access_token=response.session.access_token,
            refresh_token=response.session.refresh_token,
            user_id=response.user.id,
            email=response.user.email,
        )

    async def sign_out(self, access_token: str) -> None:
        # Admin API's sign_out(jwt) revokes the session directly from just the
        # access token -- no refresh token needed, unlike the regular client's
        # sign_out() which requires set_session() first (and both tokens).
        admin_client = get_supabase().get_admin_client()
        try:
            admin_client.auth.admin.sign_out(access_token)
        except AuthApiError as e:
            raise AuthError(str(e)) from e
        logger.info("Signed out")
