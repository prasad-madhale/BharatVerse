"""Tests for how create_app wires the middleware, using the real routes."""

import logging

import pytest
from fastapi.testclient import TestClient

from backend.config import Settings
from backend.main import create_app


def settings(**overrides):
    return Settings(
        supabase_url="https://test.supabase.co",
        supabase_anon_key="test-anon",
        supabase_service_role_key="test-service",
        **overrides,
    )


@pytest.fixture
def restore_backend_logger():
    backend = logging.getLogger("backend")
    handlers, level = backend.handlers[:], backend.level
    yield
    backend.handlers, backend.level = handlers, level


class TestCreateApp:
    def test_enforces_the_configured_limit_on_the_real_routes(self):
        client = TestClient(create_app(settings(rate_limit_requests_per_minute=2)))

        assert [client.get("/openapi.json").status_code for _ in range(3)] == [200, 200, 429]
        assert client.get("/health").status_code == 200

    def test_a_refusal_still_carries_the_cors_headers_a_browser_needs(self):
        client = TestClient(create_app(settings(rate_limit_requests_per_minute=1)))
        origin = {"Origin": "http://localhost:8765"}
        client.get("/openapi.json", headers=origin)

        refused = client.get("/openapi.json", headers=origin)

        assert refused.status_code == 429
        assert refused.headers["access-control-allow-origin"] == "*"

    def test_a_limit_of_zero_leaves_the_routes_alone(self):
        client = TestClient(create_app(settings(rate_limit_requests_per_minute=0)))

        assert [client.get("/openapi.json").status_code for _ in range(10)] == [200] * 10

    def test_logs_each_request(self, caplog):
        client = TestClient(create_app(settings()))

        with caplog.at_level(logging.INFO, logger="backend.requests"):
            client.get("/health")

        assert [r.getMessage() for r in caplog.records if r.name == "backend.requests"] == ["GET /health 200"]

    def test_applies_the_configured_log_level(self, restore_backend_logger):
        create_app(settings(log_level="WARNING"))

        assert logging.getLogger("backend").level == logging.WARNING
