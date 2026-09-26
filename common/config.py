"""
LLM configuration for the content pipeline (scrapper/). Kept separate from backend/config.py so
the pipeline doesn't have to depend on the backend service (which also requires Supabase
credentials the scraper has no need for).
"""

from pathlib import Path
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict

# Resolve relative to this file, not the process's CWD, so `.env` loads
# correctly no matter which service/directory the app is started from.
_REPO_ROOT_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


class LLMSettings(BaseSettings):
    """LLM provider configuration loaded from environment variables."""

    llm_provider: str = "gemini"  # Options: "gemini", "anthropic", "openai", "groq", "openrouter", "ollama"

    gemini_api_key: Optional[str] = None
    anthropic_api_key: Optional[str] = None
    openai_api_key: Optional[str] = None
    groq_api_key: Optional[str] = None
    openrouter_api_key: Optional[str] = None  # https://openrouter.ai/settings/keys
    ollama_base_url: str = "http://localhost:11434"  # a local, self-hosted model -- no API key

    llm_model: Optional[str] = None  # Auto-selected based on provider if not specified

    critic_enabled: bool = True  # off skips the editorial critic pass, for cheap local runs
    # None on either of these means the critic's text review uses the same provider/model as
    # generation (llm_provider/llm_model) -- set both to review with a different model instead.
    critic_llm_provider: Optional[str] = None
    critic_llm_model: Optional[str] = None

    image_sourcing_enabled: bool = True  # off skips attaching images, for cheap local runs
    target_image_count: int = 3  # 1 featured + up to 2 inline
    min_images_to_proceed: int = 1  # publish with fewer than target_image_count rather than block
    min_image_width: int = 500  # pixels; below this a candidate is rejected

    image_cohesion_check_enabled: bool = True  # off skips the critic's image-cohesion pass
    # Cohesion checks are frequent (one per image, up to target_image_count, per critic round) --
    # default to the local, free, already-vision-capable ollama model rather than the paid
    # provider the rest of the pipeline uses. image_cohesion_llm_model is None = that provider's
    # own default model (e.g. ollama's qwen3.5:9b); set it to pick a specific model on whatever
    # provider image_cohesion_llm_provider names.
    image_cohesion_llm_provider: str = "ollama"
    image_cohesion_llm_model: Optional[str] = None

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
