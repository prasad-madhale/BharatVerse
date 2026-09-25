"""
Unit tests for LLM provider.

Tests provider selection, model defaults, and initialization logic with mocked clients.
"""

import pytest
from unittest.mock import patch, MagicMock
from common.llm_provider import LLMProvider, get_llm_provider


class TestLLMProviderInitialization:
    """Test LLMProvider initialization and provider selection."""

    @patch('common.llm_provider.get_llm_settings')
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
        assert provider.model == "gemini-2.5-flash"
        mock_genai_configure.assert_called_once_with(api_key="test-gemini-key")

    @patch('common.llm_provider.get_llm_settings')
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
        assert provider.model == "claude-sonnet-5"
        mock_anthropic_class.assert_called_once_with(api_key="test-anthropic-key")
        assert provider.client == mock_client

    @patch('common.llm_provider.get_llm_settings')
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

    @patch('common.llm_provider.get_llm_settings')
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
        assert provider.model == "llama-3.3-70b-versatile"
        mock_groq_class.assert_called_once_with(api_key="test-groq-key")

    @patch('common.llm_provider.get_llm_settings')
    def test_unsupported_provider_raises_error(self, mock_get_settings):
        """Test unsupported provider raises ValueError."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "unsupported_provider"
        mock_get_settings.return_value = mock_settings

        with pytest.raises(ValueError, match="Unsupported LLM provider"):
            LLMProvider()

    @patch('common.llm_provider.get_llm_settings')
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

    @patch('common.llm_provider.get_llm_settings')
    @patch('google.generativeai.configure')
    def test_gemini_default_model(self, mock_configure, mock_get_settings):
        """Test Gemini uses correct default model."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "gemini"
        mock_settings.gemini_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        provider = LLMProvider()
        assert provider.model == "gemini-2.5-flash"

    @patch('common.llm_provider.get_llm_settings')
    @patch('anthropic.Anthropic')
    def test_anthropic_default_model(self, mock_anthropic, mock_get_settings):
        """Test Anthropic uses correct default model."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "anthropic"
        mock_settings.anthropic_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        provider = LLMProvider()
        assert provider.model == "claude-sonnet-5"


class TestGetLLMProvider:
    """Test get_llm_provider() lazy-loading behavior."""

    @patch('common.llm_provider.get_llm_settings')
    @patch('google.generativeai.configure')
    def test_get_llm_provider_lazy_loads(self, mock_configure, mock_get_settings):
        """Test get_llm_provider() creates instance on first call."""
        # Reset global state
        import common.llm_provider
        common.llm_provider._llm_provider = None

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


class TestGenerateText:
    """Test generate_text() for each provider branch."""

    @patch('common.llm_provider.get_llm_settings')
    @patch('google.generativeai.GenerativeModel')
    @patch('google.generativeai.configure')
    async def test_gemini_generate_text(self, mock_configure, mock_model_class, mock_get_settings):
        mock_settings = MagicMock()
        mock_settings.llm_provider = "gemini"
        mock_settings.gemini_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_model_instance = MagicMock()
        mock_model_instance.generate_content.return_value = MagicMock(text="Generated gemini text")
        mock_model_class.return_value = mock_model_instance

        provider = LLMProvider()
        result = await provider.generate_text("prompt")

        assert result == "Generated gemini text"
        mock_model_class.assert_called_once_with("gemini-2.5-flash")
        mock_model_instance.generate_content.assert_called_once_with("prompt")

    @patch('common.llm_provider.get_llm_settings')
    @patch('anthropic.Anthropic')
    async def test_anthropic_generate_text(self, mock_anthropic_class, mock_get_settings):
        mock_settings = MagicMock()
        mock_settings.llm_provider = "anthropic"
        mock_settings.anthropic_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_client = MagicMock()
        text_block = MagicMock(type="text", text="Generated anthropic text")
        mock_client.messages.create.return_value = MagicMock(content=[text_block])
        mock_anthropic_class.return_value = mock_client

        provider = LLMProvider()
        result = await provider.generate_text("prompt", max_tokens=500)

        assert result == "Generated anthropic text"
        mock_client.messages.create.assert_called_once_with(
            model="claude-sonnet-5",
            max_tokens=500,
            messages=[{"role": "user", "content": "prompt"}],
        )

    @patch('common.llm_provider.get_llm_settings')
    @patch('anthropic.Anthropic')
    async def test_anthropic_generate_text_passes_effort_through_output_config(
        self, mock_anthropic_class, mock_get_settings
    ):
        """effort="medium" caps adaptive-thinking depth for structured-output tasks (critic
        review, revision) -- see llm_provider.py's _anthropic_kwargs docstring."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "anthropic"
        mock_settings.anthropic_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_client = MagicMock()
        text_block = MagicMock(type="text", text="Generated anthropic text")
        mock_client.messages.create.return_value = MagicMock(content=[text_block])
        mock_anthropic_class.return_value = mock_client

        provider = LLMProvider()
        await provider.generate_text("prompt", max_tokens=500, effort="medium")

        mock_client.messages.create.assert_called_once_with(
            model="claude-sonnet-5",
            max_tokens=500,
            output_config={"effort": "medium"},
            messages=[{"role": "user", "content": "prompt"}],
        )

    @patch('common.llm_provider.get_llm_settings')
    @patch('anthropic.Anthropic')
    async def test_anthropic_generate_text_omits_output_config_when_effort_not_given(
        self, mock_anthropic_class, mock_get_settings
    ):
        mock_settings = MagicMock()
        mock_settings.llm_provider = "anthropic"
        mock_settings.anthropic_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_client = MagicMock()
        text_block = MagicMock(type="text", text="Generated anthropic text")
        mock_client.messages.create.return_value = MagicMock(content=[text_block])
        mock_anthropic_class.return_value = mock_client

        provider = LLMProvider()
        await provider.generate_text("prompt")

        assert "output_config" not in mock_client.messages.create.call_args.kwargs

    @patch('common.llm_provider.get_llm_settings')
    @patch('anthropic.Anthropic')
    async def test_anthropic_generate_text_skips_leading_thinking_block(self, mock_anthropic_class, mock_get_settings):
        """Extended-thinking-capable models can put a ThinkingBlock before the TextBlock."""
        mock_settings = MagicMock()
        mock_settings.llm_provider = "anthropic"
        mock_settings.anthropic_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_client = MagicMock()
        thinking_block = MagicMock(type="thinking")
        del thinking_block.text  # ThinkingBlock has no .text attribute
        text_block = MagicMock(type="text", text="Generated anthropic text")
        mock_client.messages.create.return_value = MagicMock(content=[thinking_block, text_block])
        mock_anthropic_class.return_value = mock_client

        provider = LLMProvider()
        result = await provider.generate_text("prompt")

        assert result == "Generated anthropic text"

    @patch('common.llm_provider.get_llm_settings')
    @patch('openai.OpenAI')
    async def test_openai_generate_text(self, mock_openai_class, mock_get_settings):
        mock_settings = MagicMock()
        mock_settings.llm_provider = "openai"
        mock_settings.openai_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_client = MagicMock()
        mock_choice = MagicMock(message=MagicMock(content="Generated openai text"))
        mock_client.chat.completions.create.return_value = MagicMock(choices=[mock_choice])
        mock_openai_class.return_value = mock_client

        provider = LLMProvider()
        result = await provider.generate_text("prompt")

        assert result == "Generated openai text"

    @patch('common.llm_provider.get_llm_settings')
    @patch('groq.Groq')
    async def test_groq_generate_text(self, mock_groq_class, mock_get_settings):
        mock_settings = MagicMock()
        mock_settings.llm_provider = "groq"
        mock_settings.groq_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_client = MagicMock()
        mock_choice = MagicMock(message=MagicMock(content="Generated groq text"))
        mock_client.chat.completions.create.return_value = MagicMock(choices=[mock_choice])
        mock_groq_class.return_value = mock_client

        provider = LLMProvider()
        result = await provider.generate_text("prompt")

        assert result == "Generated groq text"

    async def test_unsupported_provider_raises_error(self):
        """The provider-branch else in generate_text is defensive/unreachable via normal
        construction (init already raises for unsupported providers) -- bypass __init__
        via __new__ to exercise it directly."""
        provider = LLMProvider.__new__(LLMProvider)
        provider.provider = "unknown"
        provider.client = MagicMock()
        provider.model = "some-model"

        with pytest.raises(ValueError, match="Unsupported provider"):
            await provider.generate_text("prompt")


class TestGenerateTextWithImage:
    """Test generate_text_with_image() -- used by scrapper/image_sourcing.py's relevance check."""

    @patch('common.llm_provider.get_llm_settings')
    @patch('google.generativeai.GenerativeModel')
    @patch('google.generativeai.configure')
    async def test_gemini_generate_text_with_image(self, mock_configure, mock_model_class, mock_get_settings):
        mock_settings = MagicMock()
        mock_settings.llm_provider = "gemini"
        mock_settings.gemini_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_model_instance = MagicMock()
        mock_model_instance.generate_content.return_value = MagicMock(text='{"relevant": true}')
        mock_model_class.return_value = mock_model_instance

        provider = LLMProvider()
        result = await provider.generate_text_with_image("prompt", b"fake-bytes", "image/jpeg")

        assert result == '{"relevant": true}'
        mock_model_instance.generate_content.assert_called_once_with(
            ["prompt", {"mime_type": "image/jpeg", "data": b"fake-bytes"}]
        )

    @patch('common.llm_provider.get_llm_settings')
    @patch('anthropic.Anthropic')
    async def test_anthropic_generate_text_with_image(self, mock_anthropic_class, mock_get_settings):
        mock_settings = MagicMock()
        mock_settings.llm_provider = "anthropic"
        mock_settings.anthropic_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_client = MagicMock()
        text_block = MagicMock(type="text", text='{"relevant": false}')
        mock_client.messages.create.return_value = MagicMock(content=[text_block])
        mock_anthropic_class.return_value = mock_client

        provider = LLMProvider()
        result = await provider.generate_text_with_image("prompt", b"fake-bytes", "image/jpeg", max_tokens=500)

        assert result == '{"relevant": false}'
        mock_client.messages.create.assert_called_once_with(
            model="claude-sonnet-5",
            max_tokens=500,
            messages=[{
                "role": "user",
                "content": [
                    {"type": "image", "source": {
                        "type": "base64", "media_type": "image/jpeg", "data": "ZmFrZS1ieXRlcw==",
                    }},
                    {"type": "text", "text": "prompt"},
                ],
            }],
        )

    @patch('common.llm_provider.get_llm_settings')
    @patch('anthropic.Anthropic')
    async def test_anthropic_generate_text_with_image_passes_effort_through(
        self, mock_anthropic_class, mock_get_settings
    ):
        mock_settings = MagicMock()
        mock_settings.llm_provider = "anthropic"
        mock_settings.anthropic_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        mock_client = MagicMock()
        text_block = MagicMock(type="text", text='{"relevant": true}')
        mock_client.messages.create.return_value = MagicMock(content=[text_block])
        mock_anthropic_class.return_value = mock_client

        provider = LLMProvider()
        await provider.generate_text_with_image("prompt", b"fake-bytes", "image/jpeg", effort="medium")

        assert mock_client.messages.create.call_args.kwargs["output_config"] == {"effort": "medium"}

    @patch('common.llm_provider.get_llm_settings')
    @patch('openai.OpenAI')
    async def test_openai_not_implemented(self, mock_openai_class, mock_get_settings):
        mock_settings = MagicMock()
        mock_settings.llm_provider = "openai"
        mock_settings.openai_api_key = "test-key"
        mock_settings.llm_model = None
        mock_get_settings.return_value = mock_settings

        provider = LLMProvider()

        with pytest.raises(NotImplementedError):
            await provider.generate_text_with_image("prompt", b"fake-bytes", "image/jpeg")


class TestOllamaProvider:
    """The local, self-hosted provider -- no SDK, reached over its own REST API."""

    def _mock_settings(self):
        settings = MagicMock()
        settings.llm_provider = "ollama"
        settings.ollama_base_url = "http://localhost:11434"
        settings.llm_model = None
        return settings

    @patch('common.llm_provider.get_llm_settings')
    def test_default_model(self, mock_get_settings):
        mock_get_settings.return_value = self._mock_settings()

        provider = LLMProvider()

        assert provider.model == "qwen3.5:9b"
        assert provider.client is None  # no SDK client -- REST calls only

    @patch('common.llm_provider.get_llm_settings')
    @patch('common.llm_provider.requests.post')
    async def test_generate_text(self, mock_post, mock_get_settings):
        mock_get_settings.return_value = self._mock_settings()
        mock_post.return_value = MagicMock(
            json=lambda: {"message": {"content": '{"ok": true}'}},
        )

        provider = LLMProvider()
        result = await provider.generate_text("prompt", max_tokens=2000)

        assert result == '{"ok": true}'
        call = mock_post.call_args
        assert call.args[0] == "http://localhost:11434/api/chat"
        assert call.kwargs["json"]["model"] == "qwen3.5:9b"
        assert call.kwargs["json"]["messages"] == [{"role": "user", "content": "prompt"}]
        assert call.kwargs["json"]["think"] is False
        assert call.kwargs["json"]["options"] == {"num_predict": 2000}
        assert call.kwargs["timeout"] == 300

    @patch('common.llm_provider.get_llm_settings')
    @patch('common.llm_provider.requests.post')
    async def test_generate_text_with_image(self, mock_post, mock_get_settings):
        mock_get_settings.return_value = self._mock_settings()
        mock_post.return_value = MagicMock(
            json=lambda: {"message": {"content": '{"cohesive": true}'}},
        )

        provider = LLMProvider()
        result = await provider.generate_text_with_image("prompt", b"fake-bytes", "image/jpeg")

        assert result == '{"cohesive": true}'
        payload = mock_post.call_args.kwargs["json"]
        assert payload["messages"][0]["images"] == ["ZmFrZS1ieXRlcw=="]
        assert payload["options"] == {"num_predict": 8000}  # generate_text_with_image's default

    @patch('common.llm_provider.get_llm_settings')
    def test_provider_override_does_not_disturb_the_default(self, mock_get_settings):
        """LLMProvider(provider=...) is used to run one step against a different provider than
        the rest of the pipeline -- confirm the no-arg default still reads settings as before."""
        settings = self._mock_settings()
        settings.llm_provider = "gemini"
        settings.gemini_api_key = "test-key"
        mock_get_settings.return_value = settings

        with patch('google.generativeai.configure'):
            default_provider = LLMProvider()
            overridden_provider = LLMProvider(provider="ollama")

        assert default_provider.provider == "gemini"
        assert overridden_provider.provider == "ollama"
