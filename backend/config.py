"""
Configuration management for BharatVerse backend.

Loads settings from environment variables using pydantic-settings.
"""

from pathlib import Path
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict

# Resolve relative to this file, not the process's CWD, so `.env` loads
# correctly regardless of whether the app is started from the repo root,
# from backend/, or anywhere else.
_REPO_ROOT_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


class Settings(BaseSettings):
    """
    Application settings loaded from environment variables.
    """

    # Application
    app_name: str = "BharatVerse API"
    app_version: str = "0.1.0"
    debug: bool = False

    # API
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    api_prefix: str = "/api/v1"

    # Note: LLM provider/model/API key configuration lives in common.config.LLMSettings,
    # not here -- it's shared with the scrapper content pipeline (see common/config.py).

    # Supabase (Supabase Auth handles authentication and OAuth directly;
    # Google/Facebook OAuth providers are configured in the Supabase dashboard,
    # not via backend env vars)
    supabase_url: str
    supabase_anon_key: str
    supabase_service_role_key: str

    # Content Pipeline
    articles_storage_bucket: str = "articles"  # Supabase Storage bucket
    scraping_rate_limit_seconds: int = 2
    max_scraping_retries: int = 3

    # CORS
    cors_origins: list[str] = ["*"]

    # Rate Limiting
    rate_limit_requests_per_minute: int = 100

    model_config = SettingsConfigDict(
        env_file=_REPO_ROOT_ENV_FILE,
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore"
    )


# Global settings instance (lazy-loaded)
_settings: Optional[Settings] = None


def get_settings() -> Settings:
    """
    Get the global settings instance (lazy-loaded).

    Creates the settings instance on first access, allowing imports
    to succeed even when .env file is missing (useful for CI/testing).

    Returns:
        Settings: The application settings
    """
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings
