"""Tests for rate limiting and request logging, on small apps built with the real middleware."""

import asyncio
import logging

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from backend.api.middleware import add_request_middleware


class FromHeader:
    """Stands in for a server: takes the client address from an `x-client` header ('none' for no address at all)."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http":
            address = dict(scope["headers"]).get(b"x-client")
            if address:
                scope["client"] = None if address == b"none" else (address.decode(), 1234)
        await self.app(scope, receive, send)


def build_app(limit):
    app = FastAPI()
    add_request_middleware(app, limit)

    @app.get("/ping")
    async def ping():
        return {"ok": True}

    @app.get("/health")
    async def health():
        return {"status": "ok"}

    @app.get("/slow")
    async def slow():
        await asyncio.sleep(0.05)
        return {"ok": True}

    @app.get("/bad")
    async def bad():
        raise HTTPException(status_code=400)

    @app.get("/boom")
    async def boom():
        raise RuntimeError("boom")

    return FromHeader(app)


def requests_logged(caplog):
    return [r for r in caplog.records if r.name == "backend.requests"]


class TestRateLimit:
    def test_refuses_requests_over_the_limit_and_says_when_to_retry(self):
        client = TestClient(build_app(3))

        assert [client.get("/ping").status_code for _ in range(3)] == [200, 200, 200]
        refused = client.get("/ping")

        assert refused.status_code == 429
        assert 1 <= int(refused.headers["Retry-After"]) <= 60
        assert "Too many requests" in refused.json()["detail"]

    def test_never_refuses_the_health_check(self):
        client = TestClient(build_app(1))
        client.get("/ping")

        assert [client.get("/health").status_code for _ in range(5)] == [200] * 5

    def test_health_checks_do_not_use_up_a_clients_allowance(self):
        client = TestClient(build_app(1))
        for _ in range(5):
            client.get("/health")

        assert client.get("/ping").status_code == 200

    def test_counts_each_client_address_separately(self):
        client = TestClient(build_app(1))
        first, second = {"x-client": "10.0.0.1"}, {"x-client": "10.0.0.2"}

        assert client.get("/ping", headers=first).status_code == 200
        assert client.get("/ping", headers=first).status_code == 429
        assert client.get("/ping", headers=second).status_code == 200

    def test_groups_requests_with_no_address_together(self):
        client = TestClient(build_app(1))
        nobody = {"x-client": "none"}

        assert client.get("/ping", headers=nobody).status_code == 200
        assert client.get("/ping", headers=nobody).status_code == 429

    @pytest.mark.parametrize("limit", [0, -5])
    def test_a_limit_of_zero_or_less_turns_it_off(self, limit):
        client = TestClient(build_app(limit))

        assert [client.get("/ping").status_code for _ in range(20)] == [200] * 20


class TestRequestLogging:
    def test_logs_method_path_status_duration_and_client(self, caplog):
        client = TestClient(build_app(0))

        with caplog.at_level(logging.INFO, logger="backend.requests"):
            client.get("/ping?q=private", headers={"x-client": "10.0.0.7"})

        [entry] = requests_logged(caplog)
        assert entry.levelno == logging.INFO
        assert entry.getMessage() == "GET /ping 200"
        assert (entry.method, entry.path, entry.status, entry.client) == ("GET", "/ping", 200, "10.0.0.7")
        assert isinstance(entry.duration_ms, float) and entry.duration_ms >= 0

    def test_leaves_the_query_string_out_of_the_log(self, caplog):
        client = TestClient(build_app(0))

        with caplog.at_level(logging.INFO, logger="backend.requests"):
            client.get("/ping?q=private")

        assert "private" not in str(requests_logged(caplog)[0].__dict__)

    def test_the_duration_covers_the_handler(self, caplog):
        client = TestClient(build_app(0))

        with caplog.at_level(logging.INFO, logger="backend.requests"):
            client.get("/slow")

        assert requests_logged(caplog)[0].duration_ms >= 45

    def test_names_a_request_with_no_address(self, caplog):
        client = TestClient(build_app(0))

        with caplog.at_level(logging.INFO, logger="backend.requests"):
            client.get("/ping", headers={"x-client": "none"})

        assert requests_logged(caplog)[0].client == "unknown"

    def test_client_errors_are_warnings(self, caplog):
        client = TestClient(build_app(0))

        with caplog.at_level(logging.INFO, logger="backend.requests"):
            client.get("/missing")

        [entry] = requests_logged(caplog)
        assert (entry.levelno, entry.status) == (logging.WARNING, 404)

    def test_a_bad_request_is_a_warning_too(self, caplog):
        client = TestClient(build_app(0))

        with caplog.at_level(logging.INFO, logger="backend.requests"):
            client.get("/bad")

        assert requests_logged(caplog)[0].levelno == logging.WARNING

    def test_refusals_are_logged_as_warnings_too(self, caplog):
        client = TestClient(build_app(1))
        with caplog.at_level(logging.INFO, logger="backend.requests"):
            client.get("/ping")
            caplog.clear()

            client.get("/ping")

        [entry] = requests_logged(caplog)
        assert (entry.levelno, entry.status) == (logging.WARNING, 429)

    def test_a_crash_is_an_error_with_its_traceback(self, caplog):
        client = TestClient(build_app(0), raise_server_exceptions=False)

        with caplog.at_level(logging.INFO, logger="backend.requests"):
            response = client.get("/boom")

        [entry] = requests_logged(caplog)
        assert response.status_code == 500
        assert (entry.levelno, entry.status) == (logging.ERROR, 500)
        assert entry.exc_info is not None and "boom" in str(entry.exc_info[1])
