"""
Shared FastAPI dependencies for protecting endpoints.

get_current_user isn't consumed by any endpoint yet -- Phase 3 (likes) will
be the first to use it -- but it's built and tested now per the roadmap.
"""

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from gotrue.errors import AuthApiError
from gotrue.types import User

from backend.database import get_supabase

security = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> User:
    """
    Verify the bearer token against Supabase Auth and return the user it
    belongs to. Raises 401 on any missing/invalid/expired token.

    This is a network round-trip to Supabase's Auth server per call (not
    local JWT verification) -- always reflects real-time session state
    (e.g. a token revoked by sign-out), at the cost of per-request latency.
    """
    try:
        response = get_supabase().get_client().auth.get_user(credentials.credentials)
    except AuthApiError as e:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from e

    if response is None or response.user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    return response.user
