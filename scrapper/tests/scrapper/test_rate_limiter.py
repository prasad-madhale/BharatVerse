"""
Unit tests for RateLimiter.

Tests rate limiting logic without external dependencies.
"""

import pytest
import asyncio
import time
from scrapper.web_scraper import RateLimiter


class TestRateLimiter:
    """Test RateLimiter rate limiting behavior."""

    def test_rate_limiter_initialization(self):
        """Test RateLimiter initializes with correct interval."""
        limiter = RateLimiter(requests_per_second=2.0)
        assert limiter.min_interval == 0.5  # 1/2 = 0.5 seconds

        limiter2 = RateLimiter(requests_per_second=0.5)
        assert limiter2.min_interval == 2.0  # 1/0.5 = 2 seconds

    @pytest.mark.asyncio
    async def test_rate_limiter_first_request_no_wait(self):
        """Test first request doesn't wait."""
        limiter = RateLimiter(requests_per_second=1.0)

        start = time.time()
        await limiter.wait()
        elapsed = time.time() - start

        # First request should be immediate (< 0.1 seconds)
        assert elapsed < 0.1

    @pytest.mark.asyncio
    async def test_rate_limiter_enforces_minimum_interval(self):
        """Test rate limiter enforces minimum interval between requests."""
        limiter = RateLimiter(requests_per_second=2.0)  # 0.5 second interval

        # First request
        await limiter.wait()

        # Second request should wait
        start = time.time()
        await limiter.wait()
        elapsed = time.time() - start

        # Should wait approximately 0.5 seconds (allow 0.1s tolerance)
        assert 0.4 <= elapsed <= 0.6

    @pytest.mark.asyncio
    async def test_rate_limiter_multiple_requests(self):
        """Test rate limiter works correctly for multiple requests."""
        limiter = RateLimiter(requests_per_second=5.0)  # 0.2 second interval

        start = time.time()

        # Make 3 requests
        await limiter.wait()
        await limiter.wait()
        await limiter.wait()

        elapsed = time.time() - start

        # Should take approximately 0.4 seconds (2 intervals)
        # First request is immediate, then 2 waits of 0.2s each
        assert 0.3 <= elapsed <= 0.5

    @pytest.mark.asyncio
    async def test_rate_limiter_respects_natural_delays(self):
        """Test rate limiter doesn't wait if enough time has passed naturally."""
        limiter = RateLimiter(requests_per_second=2.0)  # 0.5 second interval

        # First request
        await limiter.wait()

        # Wait longer than the interval
        await asyncio.sleep(0.6)

        # Second request should not wait
        start = time.time()
        await limiter.wait()
        elapsed = time.time() - start

        # Should be immediate since we already waited 0.6s
        assert elapsed < 0.1
