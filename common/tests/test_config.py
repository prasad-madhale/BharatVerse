"""
Unit tests for shared LLM settings lazy-loading.
"""

import common.config
from common.config import LLMSettings, get_llm_settings


class TestGetLLMSettings:
    def test_lazy_loads_and_caches_singleton(self):
        common.config._llm_settings = None

        settings1 = get_llm_settings()
        assert isinstance(settings1, LLMSettings)

        settings2 = get_llm_settings()
        assert settings1 is settings2
