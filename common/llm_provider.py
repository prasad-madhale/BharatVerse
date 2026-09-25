"""
LLM Provider abstraction layer.

Supports multiple LLM providers with a unified interface:
- Google Gemini (FREE - default)
- Anthropic Claude
- OpenAI
- Groq

Used by scrapper/ (topic and article generation) -- see common/config.py for where its
settings come from.
"""

import asyncio
import base64

import requests

from common.config import get_llm_settings


class LLMProvider:
    """
    Unified interface for different LLM providers.
    """

    def __init__(self, provider: str | None = None):
        """provider overrides settings.llm_provider -- used to run a specific step (e.g. the
        image-cohesion check) against a different provider than the rest of the pipeline."""
        settings = get_llm_settings()
        self.provider = (provider or settings.llm_provider).lower()
        self.ollama_base_url = settings.ollama_base_url
        self.client = self._initialize_client()
        self.model = self._get_model()

    def _initialize_client(self):
        """Initialize the appropriate LLM client based on provider."""
        settings = get_llm_settings()
        if self.provider == "gemini":
            import google.generativeai as genai
            genai.configure(api_key=settings.gemini_api_key)
            return genai

        elif self.provider == "anthropic":
            from anthropic import Anthropic
            return Anthropic(api_key=settings.anthropic_api_key)

        elif self.provider == "openai":
            from openai import OpenAI
            return OpenAI(api_key=settings.openai_api_key)

        elif self.provider == "groq":
            from groq import Groq
            return Groq(api_key=settings.groq_api_key)

        elif self.provider == "ollama":
            return None  # no SDK client -- generate_text[_with_image] call its REST API directly

        else:
            raise ValueError(f"Unsupported LLM provider: {self.provider}")

    def _get_model(self) -> str:
        """Get the model name for the provider."""
        settings = get_llm_settings()
        if settings.llm_model:
            return settings.llm_model

        # Default models for each provider. The gemini-1.x line has been
        # fully retired by Google; gemini-2.5-flash is confirmed available
        # (verified against ListModels as of 2026-07). llama-3.1-70b-versatile
        # has been retired by Groq; llama-3.3-70b-versatile is its confirmed
        # available successor (verified against client.models.list() as of
        # 2026-07), though it undershoots this pipeline's word-count target
        # badly in practice -- prefer anthropic/gemini when quality matters.
        # claude-sonnet-5 chosen over Haiku for grounding/instruction-following
        # quality; article volume is low enough (~1/day) that cost is
        # negligible either way. The openai default below is unverified
        # against a live API key and may be stale -- confirm before relying
        # on it. qwen3.5:9b is whatever's pulled locally (`ollama list`) --
        # confirmed vision-capable, used for the image-cohesion check.
        defaults = {
            "gemini": "gemini-2.5-flash",
            "anthropic": "claude-sonnet-5",
            "openai": "gpt-3.5-turbo",
            "groq": "llama-3.3-70b-versatile",
            "ollama": "qwen3.5:9b",
        }
        return defaults.get(self.provider, "")

    async def generate_text(self, prompt: str, max_tokens: int = 4000, effort: str | None = None) -> str:
        """
        Generate text using the configured LLM provider.

        Args:
            prompt: The input prompt
            max_tokens: Maximum tokens to generate
            effort: Anthropic-only. claude-sonnet-5 runs adaptive thinking at effort="high" by
                default, and max_tokens is a hard cap on thinking *plus* the response -- on a
                long, complex prompt this can leave no room for the actual answer (see
                _anthropic_kwargs). Pass "medium" for well-specified, structured-output tasks
                (a JSON verdict or a schema-following revision) that don't need exploratory
                reasoning depth; leave unset (implicit "high") for open-ended creative work.
                Ignored by every other provider.

        Returns:
            Generated text
        """
        if self.provider == "gemini":
            model = self.client.GenerativeModel(self.model)
            response = model.generate_content(prompt)
            return response.text

        elif self.provider == "anthropic":
            response = self.client.messages.create(
                **self._anthropic_kwargs(max_tokens, effort),
                messages=[{"role": "user", "content": prompt}]
            )
            # Extended-thinking-capable models (e.g. claude-sonnet-5) can put a
            # ThinkingBlock before the actual TextBlock in content -- content[0]
            # isn't reliably the answer, so find the text block(s) explicitly.
            text_blocks = [block.text for block in response.content if block.type == "text"]
            return "".join(text_blocks)

        elif self.provider == "openai":
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=max_tokens
            )
            return response.choices[0].message.content

        elif self.provider == "groq":
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=max_tokens
            )
            return response.choices[0].message.content

        elif self.provider == "ollama":
            return await self._ollama_chat(prompt, max_tokens=max_tokens)

        else:
            raise ValueError(f"Unsupported provider: {self.provider}")

    async def generate_text_with_image(
        self, prompt: str, image_bytes: bytes, media_type: str, max_tokens: int = 8000,
        effort: str | None = None,
    ) -> str:
        """
        Like generate_text, but with an image attached -- used by
        scrapper/image_sourcing.py's relevance check and article_critic.py's
        image-cohesion check. gemini, anthropic and ollama are implemented;
        openai/groq raise NotImplementedError until one of them is needed.

        max_tokens defaults to 8000, matching article_critic.py's measured
        finding: claude-sonnet-5's extended thinking can consume a too-small
        budget entirely and return no text at all, even for a short answer --
        if this ever comes back empty, effort="medium" (see generate_text) is
        the other lever, alongside max_tokens, that Anthropic's own docs
        recommend for this exact failure mode.
        """
        if self.provider == "gemini":
            model = self.client.GenerativeModel(self.model)
            response = model.generate_content(
                [prompt, {"mime_type": media_type, "data": image_bytes}]
            )
            return response.text

        elif self.provider == "anthropic":
            response = self.client.messages.create(
                **self._anthropic_kwargs(max_tokens, effort),
                messages=[{
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": base64.b64encode(image_bytes).decode("ascii"),
                            },
                        },
                        {"type": "text", "text": prompt},
                    ],
                }],
            )
            text_blocks = [block.text for block in response.content if block.type == "text"]
            return "".join(text_blocks)

        elif self.provider == "ollama":
            return await self._ollama_chat(prompt, image_bytes=image_bytes, max_tokens=max_tokens)

        else:
            raise NotImplementedError(
                f"generate_text_with_image isn't implemented for provider: {self.provider}"
            )

    def _anthropic_kwargs(self, max_tokens: int, effort: str | None) -> dict:
        """model/max_tokens, plus output_config.effort when given -- see generate_text's
        effort docstring for why: claude-sonnet-5 runs adaptive thinking by default and
        max_tokens caps thinking + the response together, so a long prompt at the default
        effort="high" can exhaust the budget on thinking alone and return empty text."""
        kwargs: dict = {"model": self.model, "max_tokens": max_tokens}
        if effort is not None:
            kwargs["output_config"] = {"effort": effort}
        return kwargs

    async def _ollama_chat(self, prompt: str, max_tokens: int, image_bytes: bytes | None = None) -> str:
        """Shared by generate_text and generate_text_with_image for the ollama provider -- a
        local, self-hosted model with no API key, reached over its own REST API.

        think=False: these prompts all ask for a direct answer -- a compact JSON verdict, or a
        structured JSON article -- not open-ended reasoning -- measured against qwen3.5:9b, a
        warm image-understanding call took ~9s with thinking off versus over 20s with it on, for
        no benefit to a one-line answer.

        timeout=300, num_predict=max_tokens: a full ~2000-word article generation call measured
        ~76s and a revision ~53s against qwen3.5:9b on this machine's GPU (CPU/GPU-bound, not
        network-bound like the hosted providers) -- the previous timeout=60 with no num_predict
        set was tuned only for the image-cohesion check's short JSON verdicts and would have
        timed out mid-generation.
        """
        message: dict = {"role": "user", "content": prompt}
        if image_bytes is not None:
            message["images"] = [base64.b64encode(image_bytes).decode("ascii")]

        def _fetch():
            response = requests.post(
                f"{self.ollama_base_url}/api/chat",
                json={
                    "model": self.model, "messages": [message], "think": False, "stream": False,
                    "options": {"num_predict": max_tokens},
                },
                timeout=300,
            )
            response.raise_for_status()
            return response.json()

        result = await asyncio.to_thread(_fetch)
        return result["message"]["content"]


# Global LLM provider instance (lazy-loaded)
_llm_provider = None


def get_llm_provider() -> LLMProvider:
    """Get the global LLM provider instance (lazy-loaded)."""
    global _llm_provider
    if _llm_provider is None:
        _llm_provider = LLMProvider()
    return _llm_provider
