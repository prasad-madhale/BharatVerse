"""
Auth request/response shapes for the backend's REST API.

Session verification (the "is this token still valid" check used to protect
future endpoints like likes) lives in backend/api/deps.py, not here -- these
are just the request/response bodies for the auth endpoints themselves.
"""

from typing import Optional
from pydantic import BaseModel, EmailStr


class SignUpRequest(BaseModel):
    email: EmailStr
    password: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class AuthResponse(BaseModel):
    """Shape returned by signup/login -- enough for the client to make
    authenticated requests and know who's signed in, nothing more."""

    access_token: str
    refresh_token: str
    user_id: str
    email: Optional[str] = None
