"""Unit tests for RateLimiter: a sliding window per client that counts only the requests it lets through."""

import pytest
from hypothesis import given, settings, strategies as st

from backend.utils.rate_limit import RateLimiter


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now

    def advance(self, seconds):
        self.now += seconds


@pytest.fixture
def clock():
    return Clock()


class TestRateLimiter:
    def test_allows_up_to_the_limit_then_refuses(self, clock):
        limiter = RateLimiter(3, window=60, clock=clock)

        assert [limiter.hit("a") for _ in range(3)] == [0.0, 0.0, 0.0]
        assert limiter.hit("a") > 0

    def test_says_how_long_until_the_oldest_request_expires(self, clock):
        limiter = RateLimiter(2, window=60, clock=clock)
        limiter.hit("a")
        clock.advance(10)
        limiter.hit("a")
        clock.advance(20)

        assert limiter.hit("a") == pytest.approx(30)  # the first request is 30 s old, so 30 s remain

    def test_allows_again_the_moment_the_oldest_request_leaves_the_window(self, clock):
        limiter = RateLimiter(1, window=60, clock=clock)
        clock.advance(5)  # so the once-a-window sweep has run by the time of the boundary, and cannot mask it
        limiter.hit("a")
        clock.advance(59.5)
        assert limiter.hit("a") > 0

        clock.advance(0.5)  # exactly one window since the first request
        assert limiter.hit("a") == 0.0

    def test_refused_requests_are_not_counted(self, clock):
        limiter = RateLimiter(1, window=60, clock=clock)
        limiter.hit("a")
        for _ in range(5):
            limiter.hit("a")  # hammering must not push the wait further out
        clock.advance(60)

        assert limiter.hit("a") == 0.0

    def test_counts_each_client_separately(self, clock):
        limiter = RateLimiter(1, window=60, clock=clock)
        limiter.hit("a")

        assert limiter.hit("a") > 0
        assert limiter.hit("b") == 0.0

    @pytest.mark.parametrize("limit", [0, -1])
    def test_rejects_a_limit_below_one(self, limit):
        with pytest.raises(ValueError):
            RateLimiter(limit)

    def test_forgets_clients_that_have_gone_quiet(self, clock):
        limiter = RateLimiter(5, window=60, clock=clock)
        for n in range(100):
            limiter.hit(f"client-{n}")
        assert len(limiter) == 100

        clock.advance(61)
        limiter.hit("newcomer")

        assert len(limiter) == 1

    def test_keeps_clients_still_inside_their_window(self, clock):
        limiter = RateLimiter(2, window=60, clock=clock)
        limiter.hit("early")
        limiter.hit("busy")
        clock.advance(50)
        limiter.hit("busy")  # its first request is old, but its last one is not
        clock.advance(20)  # 70 s after the first requests, 20 s after busy's second, and a sweep is due

        limiter.hit("newcomer")

        assert len(limiter) == 2  # busy and newcomer
        assert limiter.hit("busy") == 0.0  # still has one request left in its allowance
        assert limiter.hit("busy") > 0

    @settings(max_examples=150, deadline=None)
    @given(
        limit=st.integers(min_value=1, max_value=6),
        window=st.integers(min_value=1, max_value=30),
        requests=st.lists(st.tuples(st.integers(0, 3), st.integers(0, 12)), max_size=60),
    )
    def test_matches_a_plain_count_of_recent_allowed_requests(self, limit, window, requests):
        """A request is allowed exactly when fewer than `limit` allowed ones fall in the previous `window` seconds."""
        clock = Clock()
        limiter = RateLimiter(limit, window=window, clock=clock)
        allowed: dict[int, list[float]] = {}

        for client, gap in requests:
            clock.advance(gap)
            recent = [t for t in allowed.get(client, []) if clock.now - t < window]
            wait = limiter.hit(str(client))

            if len(recent) < limit:
                assert wait == 0.0
                allowed.setdefault(client, []).append(clock.now)
            else:
                assert wait == pytest.approx(window - (clock.now - recent[0]))
