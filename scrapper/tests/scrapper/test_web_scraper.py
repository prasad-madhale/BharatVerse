"""
Unit tests for WebScraper.
"""

import pytest
from scrapper.web_scraper import WebScraper, RateLimiter
import asyncio
import time


class TestRateLimiter:
    """Tests for RateLimiter."""
    
    @pytest.mark.asyncio
    async def test_rate_limiting(self):
        """Test that rate limiter enforces delays."""
        limiter = RateLimiter(requests_per_second=2.0)  # 2 req/sec = 0.5s interval
        
        start = time.time()
        await limiter.wait()
        await limiter.wait()
        elapsed = time.time() - start
        
        # Should take at least 0.5 seconds for second request
        assert elapsed >= 0.4  # Allow small margin
    
    @pytest.mark.asyncio
    async def test_first_request_no_delay(self):
        """Test that first request has no delay."""
        limiter = RateLimiter(requests_per_second=1.0)
        
        start = time.time()
        await limiter.wait()
        elapsed = time.time() - start
        
        # First request should be immediate
        assert elapsed < 0.1


class TestWebScraper:
    """Tests for WebScraper."""
    
    def test_init(self):
        """Test WebScraper initialization."""
        scraper = WebScraper()
        
        assert scraper.registry is not None
        assert scraper.rate_limiter is not None
        assert isinstance(scraper._robots_cache, dict)
    
    def test_list_sources(self):
        """Test listing available sources."""
        scraper = WebScraper()
        sources = scraper.list_sources()
        
        assert isinstance(sources, list)
        assert "wikipedia" in sources
        assert "archive_org" in sources
    
    @pytest.mark.asyncio
    async def test_scrape_invalid_source(self):
        """Test scraping from invalid source raises error."""
        scraper = WebScraper()
        
        with pytest.raises(ValueError, match="Source 'nonexistent' not found"):
            await scraper.scrape("nonexistent", "test topic")
    
    @pytest.mark.asyncio
    async def test_check_robots_txt(self):
        """Test robots.txt checking."""
        scraper = WebScraper()
        
        # Test with a known URL
        allowed = await scraper.check_robots_txt("https://en.wikipedia.org/wiki/Python")
        
        # Should return a boolean
        assert isinstance(allowed, bool)
