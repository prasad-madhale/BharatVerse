"""Rate limiting and request logging, applied to every route."""

import logging
import math
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from backend.utils.rate_limit import RateLimiter

logger = logging.getLogger("backend.requests")

UNLIMITED_PATHS = {"/health"}  # monitors poll this, so it must never be refused


def add_request_middleware(app: FastAPI, requests_per_minute: int) -> None:
    """Rate limits each client to `requests_per_minute` (0 turns it off), with logging outside it so refusals are logged.

    The limit is per process and per client address; behind a proxy, run uvicorn with `--proxy-headers`
    so the address is the caller's rather than the proxy's.
    """
    if requests_per_minute > 0:
        limiter = RateLimiter(requests_per_minute)

        @app.middleware("http")
        async def rate_limit(request: Request, call_next):
            wait = 0.0 if request.url.path in UNLIMITED_PATHS else limiter.hit(_client(request))
            if wait > 0:
                return JSONResponse(
                    {"detail": "Too many requests. Try again shortly."},
                    status_code=429,
                    headers={"Retry-After": str(math.ceil(wait))},
                )
            return await call_next(request)

    @app.middleware("http")
    async def log_requests(request: Request, call_next):
        started = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            _log(request, 500, started, exc_info=True)
            raise
        _log(request, response.status_code, started)
        return response


def _client(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _log(request: Request, status: int, started: float, exc_info: bool = False) -> None:
    level = logging.ERROR if status >= 500 else logging.WARNING if status >= 400 else logging.INFO
    logger.log(
        level,
        f"{request.method} {request.url.path} {status}",
        exc_info=exc_info,
        extra={
            "method": request.method,
            "path": request.url.path,
            "status": status,
            "duration_ms": round((time.perf_counter() - started) * 1000, 1),
            "client": _client(request),
        },
    )
