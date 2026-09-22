"""A sliding-window rate limiter: at most `limit` requests per client in any `window` seconds."""

import time
from collections import deque
from typing import Callable


class RateLimiter:
    def __init__(self, limit: int, window: float = 60.0, clock: Callable[[], float] = time.monotonic):
        if limit < 1:
            raise ValueError("limit must be at least 1")
        self.limit = limit
        self.window = window
        self._clock = clock
        self._hits: dict[str, deque[float]] = {}
        self._last_sweep = clock()

    def hit(self, client: str) -> float:
        """Counts a request from `client`: 0 if it is allowed, else the seconds to wait. Refusals are not counted."""
        now = self._clock()
        self._forget_quiet_clients(now)
        hits = self._hits.setdefault(client, deque())
        while hits and now - hits[0] >= self.window:
            hits.popleft()
        if len(hits) >= self.limit:
            return self.window - (now - hits[0])
        hits.append(now)
        return 0.0

    def _forget_quiet_clients(self, now: float) -> None:
        """Once a window, drops clients with nothing left to count, so memory does not grow with every address seen."""
        if now - self._last_sweep < self.window:
            return
        self._last_sweep = now
        for client in [c for c, hits in self._hits.items() if now - hits[-1] >= self.window]:
            del self._hits[client]

    def __len__(self) -> int:
        """How many clients are being tracked."""
        return len(self._hits)
