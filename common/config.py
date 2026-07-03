"""
Shared LLM configuration, used by both backend/ (semantic search embeddings)
and scrapper/ (article generation). Kept separate from backend/config.py so
the content pipeline doesn't have to depend on the backend service (which
also requires Supabase credentials the scraper has no need for).
"""

from pathlib import Path
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict

# Resolve relative to this file, not the process's CWD, so `.env` loads
# correctly no matter which service/directory the app is started from.
_REPO_ROOT_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


class LLMSettings(BaseSettings):
    """LLM provider configuration loaded from environment variables."""

    llm_provider: str = "gemini"  # Options: "gemini", "anthropic", "openai", "groq"

    gemini_api_key: Optional[str] = None
    anthropic_api_key: Optional[str] = None
    openai_api_key: Optional[str] = None
    groq_api_key: Optional[str] = None

    llm_model: Optional[str] = None  # Auto-selected based on provider if not specified

    model_config = SettingsConfigDict(
        env_file=_REPO_ROOT_ENV_FILE,
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore"
    )


# Global settings instance (lazy-loaded)
_llm_settings: Optional[LLMSettings] = None


def get_llm_settings() -> LLMSettings:
    """Get the global LLM settings instance (lazy-loaded)."""
    global _llm_settings
    if _llm_settings is None:
        _llm_settings = LLMSettings()
    return _llm_settings
