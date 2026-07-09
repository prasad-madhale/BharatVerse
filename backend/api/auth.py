"""
Auth endpoints: email/password sign-up, sign-in, sign-out.

OAuth (Google/Facebook) is deferred to a fast-follow once app registration
with those providers is underway -- see roadmap.md Phase 1.
"""

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from backend.api.deps import security
from backend.models.auth import AuthResponse, LoginRequest, SignUpRequest
from backend.services.auth_service import AuthError, AuthService

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", response_model=AuthResponse)
async def sign_up(body: SignUpRequest) -> AuthResponse:
    try:
        return await AuthService().sign_up(body.email, body.password)
    except AuthError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e


@router.post("/login", response_model=AuthResponse)
async def login(body: LoginRequest) -> AuthResponse:
    try:
        return await AuthService().sign_in(body.email, body.password)
    except AuthError as e:
        raise HTTPException(status_code=401, detail=str(e)) from e


@router.post("/logout", status_code=204)
async def logout(credentials: HTTPAuthorizationCredentials = Depends(security)) -> None:
    try:
        await AuthService().sign_out(credentials.credentials)
    except AuthError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
