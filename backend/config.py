"""
Configuration management for BharatVerse backend.

Loads settings from environment variables using pydantic-settings.
"""

import os
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict


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
    
    # Database
    database_url: str = "sqlite+aiosqlite:///./bharatverse.db"
    database_path: str = "./bharatverse.db"
    
    # LLM APIs (choose one)
    llm_provider: str = "gemini"  # Options: "gemini", "anthropic", "openai", "groq"
    
    # API Keys (provide based on llm_provider)
    gemini_api_key: Optional[str] = None
    anthropic_api_key: Optional[str] = None
    openai_api_key: Optional[str] = None
    groq_api_key: Optional[str] = None
    
    # LLM Model Configuration
    llm_model: Optional[str] = None  # Auto-selected based on provider if not specified
    
    # Authentication
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 60
    jwt_refresh_token_expire_days: int = 30
    
    # OAuth
    google_client_id: Optional[str] = None
    google_client_secret: Optional[str] = None
    facebook_app_id: Optional[str] = None
    facebook_app_secret: Optional[str] = None
    
    # Content Pipeline
    articles_storage_path: str = "./articles"
    scraping_rate_limit_seconds: int = 2
    max_scraping_retries: int = 3
    
    # CORS
    cors_origins: list[str] = ["*"]
    
    # Rate Limiting
    rate_limit_requests_per_minute: int = 100
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore"
    )


# Global settings instance
settings = Settings()


def get_settings() -> Settings:
    """
    Get the global settings instance.
    
    Returns:
        Settings: The application settings
    """
    return settings
