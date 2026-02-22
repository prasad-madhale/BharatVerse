"""
Unit tests for backend configuration.

Tests Settings validation, defaults, and error handling without external dependencies.
"""

import pytest
from pydantic import ValidationError
from pydantic_settings import SettingsConfigDict
from unittest.mock import patch
import os

from backend.config import Settings, get_settings


class TestSettings:
    """Test Settings class validation and defaults."""

    def test_settings_with_all_required_fields(self):
        """Test Settings can be created with all required fields."""
        settings = Settings(
            jwt_secret_key="test-secret-key",
            supabase_url="https://test.supabase.co",
            supabase_anon_key="test-anon-key",
            supabase_service_role_key="test-service-role-key"
        )

        assert settings.jwt_secret_key == "test-secret-key"
        assert settings.supabase_url == "https://test.supabase.co"
        assert settings.supabase_anon_key == "test-anon-key"
        assert settings.supabase_service_role_key == "test-service-role-key"

    def test_settings_missing_required_fields(self):
        """Test Settings raises ValidationError when missing fields."""
        # Clear environment and disable .env file loading
        with patch.dict(os.environ, {}, clear=True):
            # Patch model_config to disable env_file
            config = SettingsConfigDict(
                env_file=None,
                case_sensitive=False,
                extra="ignore"
            )
            with patch.object(
                Settings,
                'model_config',
                config
            ):
                with pytest.raises(ValidationError) as exc_info:
                    Settings()

                errors = exc_info.value.errors()
                error_fields = {error['loc'][0] for error in errors}

                assert 'jwt_secret_key' in error_fields
                assert 'supabase_url' in error_fields
                assert 'supabase_anon_key' in error_fields
                assert 'supabase_service_role_key' in error_fields

    def test_settings_default_values(self):
        """Test Settings applies correct default values."""
        settings = Settings(
            jwt_secret_key="test-secret",
            supabase_url="https://test.supabase.co",
            supabase_anon_key="test-anon",
            supabase_service_role_key="test-service"
        )

        # Application defaults
        assert settings.app_name == "BharatVerse API"
        assert settings.app_version == "0.1.0"
        assert settings.debug is False

        # API defaults
        assert settings.api_host == "0.0.0.0"
        assert settings.api_port == 8000
        assert settings.api_prefix == "/api/v1"

        # LLM defaults
        assert settings.llm_provider == "gemini"
        assert settings.llm_model is None

        # JWT defaults
        assert settings.jwt_algorithm == "HS256"
        assert settings.jwt_access_token_expire_minutes == 60
        assert settings.jwt_refresh_token_expire_days == 30

    def test_settings_optional_fields(self):
        """Test Settings handles optional fields correctly."""
        settings = Settings(
            jwt_secret_key="test-secret",
            supabase_url="https://test.supabase.co",
            supabase_anon_key="test-anon",
            supabase_service_role_key="test-service",
            gemini_api_key="test-gemini-key",
            llm_model="custom-model"
        )

        assert settings.gemini_api_key == "test-gemini-key"
        assert settings.llm_model == "custom-model"
        assert settings.anthropic_api_key is None
        assert settings.openai_api_key is None

    def test_settings_cors_origins_default(self):
        """Test CORS origins default to wildcard."""
        settings = Settings(
            jwt_secret_key="test-secret",
            supabase_url="https://test.supabase.co",
            supabase_anon_key="test-anon",
            supabase_service_role_key="test-service"
        )

        assert settings.cors_origins == ["*"]


class TestGetSettings:
    """Test get_settings() lazy-loading behavior."""

    def test_get_settings_lazy_loads(self):
        """Test get_settings() creates instance on first call."""
        # Reset global state
        import backend.config
        backend.config._settings = None

        with patch.dict(os.environ, {
            'JWT_SECRET_KEY': 'test-secret',
            'SUPABASE_URL': 'https://test.supabase.co',
            'SUPABASE_ANON_KEY': 'test-anon',
            'SUPABASE_SERVICE_ROLE_KEY': 'test-service'
        }, clear=True):
            settings = get_settings()
            assert settings is not None
            assert settings.jwt_secret_key == 'test-secret'

            # Second call should return same instance
            settings2 = get_settings()
            assert settings is settings2

    def test_get_settings_without_env_raises_error(self):
        """Test get_settings() raises error without env variables."""
        # Reset global state
        import backend.config
        backend.config._settings = None

        with patch.dict(os.environ, {}, clear=True):
            # Patch model_config to disable env_file
            config = SettingsConfigDict(
                env_file=None,
                case_sensitive=False,
                extra="ignore"
            )
            with patch.object(
                Settings,
                'model_config',
                config
            ):
                with pytest.raises(ValidationError):
                    get_settings()
