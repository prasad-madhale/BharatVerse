"""
Unit tests for LLM provider.

Tests provider selection, model defaults, and initialization logic with mocked clients.
"""

import pytest
from unittest.mock import patch, MagicMock
from backend.utils.llm_provider import LLMProvider, get_llm_provider


class TestLLMProviderInitialization:
    """Test LLMProvider initialization and provider selection."""

    @patch('backend.utils.llm_provider.get_settings')
    @patch('google.generativeai.configure')
    def test_gemini_provider_initialization(self, mock_genai_configure, mock_get_settings):
        """Test Gemini provider initializes correctly."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "gemini"
        mock_settings.gemini_api_key = "test-gemini-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        provider = LLMProvider()

        assert provider.provider == "gemini"
        assert provider.model == "gemini-1.5-flash"
        mock_genai_configure.assert_called_once_with(api_key="test-gemini-key")

    @patch('backend.utils.llm_provider.get_settings')
    @patch('anthropic.Anthropic')
    def test_anthropic_provider_initialization(self, mock_anthropic_class, mock_get_settings):
        """Test Anthropic provider initializes correctly."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "anthropic"
        mock_settings.anthropic_api_key = "test-anthropic-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_client = MagicMock()
        mock_anthropic_class.return_value = mock_client

        provider = LLMProvider()

        assert provider.provider == "anthropic"
        assert provider.model == "claude-3-haiku-20240307"
        mock_anthropic_class.assert_called_once_with(api_key="test-anthropic-key")
        assert provider.client == mock_client

    @patch('backend.utils.llm_provider.get_settings')
    @patch('openai.OpenAI')
    def test_openai_provider_initialization(self, mock_openai_class, mock_get_settings):
        """Test OpenAI provider initializes correctly."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "openai"
        mock_settings.openai_api_key = "test-openai-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_client = MagicMock()
        mock_openai_class.return_value = mock_client

        provider = LLMProvider()

        assert provider.provider == "openai"
        assert provider.model == "gpt-3.5-turbo"
        mock_openai_class.assert_called_once_with(api_key="test-openai-key")

    @patch('backend.utils.llm_provider.get_settings')
    @patch('groq.Groq')
    def test_groq_provider_initialization(self, mock_groq_class, mock_get_settings):
        """Test Groq provider initializes correctly."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "groq"
        mock_settings.groq_api_key = "test-groq-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_client = MagicMock()
        mock_groq_class.return_value = mock_client

        provider = LLMProvider()

        assert provider.provider == "groq"
        assert provider.model == "llama-3.1-70b-versatile"
        mock_groq_class.assert_called_once_with(api_key="test-groq-key")

    @patch('backend.utils.llm_provider.get_settings')
    def test_unsupported_provider_raises_error(self, mock_get_settings):
        """Test unsupported provider raises ValueError."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "unsupported_provider"
        mock_get_settings.return_value = mock_settings

        with pytest.raises(ValueError, match="Unsupported LLM provider"):
            LLMProvider()

    @patch('backend.utils.llm_provider.get_settings')
    @patch('google.generativeai.configure')
    def test_custom_model_override(self, mock_genai_configure, mock_get_settings):
        """Test custom model overrides default."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "gemini"
        mock_settings.gemini_api_key = "test-key"
        mock_settings.llm_model = "custom-model-name"
        mock_get_settings.return_value = mock_settings

        provider = LLMProvider()

        assert provider.model == "custom-model-name"


class TestLLMProviderModelDefaults:
    """Test default model selection for each provider."""

    @patch('backend.utils.llm_provider.get_settings')
    @patch('google.generativeai.configure')
    def test_gemini_default_model(self, mock_configure, mock_get_settings):
        """Test Gemini uses correct default model."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "gemini"
        mock_settings.gemini_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        provider = LLMProvider()
        assert provider.model == "gemini-1.5-flash"

    @patch('backend.utils.llm_provider.get_settings')
    @patch('anthropic.Anthropic')
    def test_anthropic_default_model(self, mock_anthropic, mock_get_settings):
        """Test Anthropic uses correct default model."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "anthropic"
        mock_settings.anthropic_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        provider = LLMProvider()
        assert provider.model == "claude-3-haiku-20240307"


class TestGetLLMProvider:
    """Test get_llm_provider() lazy-loading behavior."""

    @patch('backend.utils.llm_provider.get_settings')
    @patch('google.generativeai.configure')
    def test_get_llm_provider_lazy_loads(self, mock_configure, mock_get_settings):
        """Test get_llm_provider() creates instance on first call."""
        # Reset global state
        import backend.utils.llm_provider
        backend.utils.llm_provider._llm_provider = None

        mock_settings = MagicMock()
        mock_settings.llm_provider = "gemini"
        mock_settings.gemini_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        provider1 = get_llm_provider()
        assert provider1 is not None

        # Second call should return same instance
        provider2 = get_llm_provider()
        assert provider1 is provider2
