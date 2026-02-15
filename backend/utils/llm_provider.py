"""
LLM Provider abstraction layer.

Supports multiple LLM providers with a unified interface:
- Google Gemini (FREE - default)
- Anthropic Claude
- OpenAI
- Groq
"""

from typing import Optional
from backend.config import settings


class LLMProvider:
    """
    Unified interface for different LLM providers.
    """
    
    def __init__(self):
        self.provider = settings.llm_provider.lower()
        self.client = self._initialize_client()
        self.model = self._get_model()
    
    def _initialize_client(self):
        """Initialize the appropriate LLM client based on provider."""
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
        
        else:
            raise ValueError(f"Unsupported LLM provider: {self.provider}")
    
    def _get_model(self) -> str:
        """Get the model name for the provider."""
        if settings.llm_model:
            return settings.llm_model
        
        # Default models for each provider
        defaults = {
            "gemini": "gemini-1.5-flash",
            "anthropic": "claude-3-haiku-20240307",
            "openai": "gpt-3.5-turbo",
            "groq": "llama-3.1-70b-versatile"
        }
        return defaults.get(self.provider, "")
    
    async def generate_text(self, prompt: str, max_tokens: int = 2000) -> str:
        """
        Generate text using the configured LLM provider.
        
        Args:
            prompt: The input prompt
            max_tokens: Maximum tokens to generate
            
        Returns:
            Generated text
        """
        if self.provider == "gemini":
            model = self.client.GenerativeModel(self.model)
            response = model.generate_content(prompt)
            return response.text
        
        elif self.provider == "anthropic":
            response = self.client.messages.create(
                model=self.model,
                max_tokens=max_tokens,
                messages=[{"role": "user", "content": prompt}]
            )
            return response.content[0].text
        
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
        
        else:
            raise ValueError(f"Unsupported provider: {self.provider}")
    
    async def generate_embedding(self, text: str) -> list[float]:
        """
        Generate embeddings for semantic search.
        
        Args:
            text: Input text
            
        Returns:
            Embedding vector
        """
        if self.provider == "gemini":
            result = self.client.embed_content(
                model="models/embedding-001",
                content=text
            )
            return result['embedding']
        
        elif self.provider == "openai":
            response = self.client.embeddings.create(
                model="text-embedding-ada-002",
                input=text
            )
            return response.data[0].embedding
        
        else:
            # Fallback: use OpenAI for embeddings if provider doesn't support it
            from openai import OpenAI
            client = OpenAI(api_key=settings.openai_api_key)
            response = client.embeddings.create(
                model="text-embedding-ada-002",
                input=text
            )
            return response.data[0].embedding


# Global LLM provider instance
llm_provider = LLMProvider()
