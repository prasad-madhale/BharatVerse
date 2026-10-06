"""
The daily GitHub Actions pipeline's own settings: read from .github/workflows/daily-pipeline.yml and loaded the way the
run would load them, every model role resolves to Google AI Studio (the `gemini` provider) with the model meant for it. Guards against a role silently
falling back to a default the CI runner cannot serve (the image check's default is a local Ollama model).
"""

import re
from pathlib import Path

import pytest

import common.config
from common.config import LLMSettings
from scrapper.article_critic import ArticleCritic
from scrapper.article_generator import ArticleGenerator

WORKFLOW = Path(__file__).resolve().parents[3] / ".github" / "workflows" / "daily-pipeline.yml"


def pipeline_env():
    """The env block of the step that runs scrapper_main.py, as {NAME: value}."""
    text = WORKFLOW.read_text()
    step = text[text.index("name: Run the daily content pipeline"):]
    block = step[step.index("env:"):].split("\n\n")[0]
    return dict(re.findall(r"^\s+([A-Z_]+): (.+)$", block, re.M))


@pytest.fixture
def run_settings(monkeypatch):
    """The settings the workflow's run would load: its env, a stand-in key, and no developer .env."""
    env = {name: value for name, value in pipeline_env().items() if not value.startswith("${{")}
    settings = LLMSettings(_env_file=None, gemini_api_key="test-key", **{k.lower(): v for k, v in env.items()})
    monkeypatch.setattr(common.config, "_llm_settings", settings)
    return settings


def test_gemma_writes_flash_reviews_and_flash_lite_checks_the_images(run_settings):
    critic = ArticleCritic()
    generator = ArticleGenerator()

    assert (generator.llm_provider.provider, generator.llm_provider.model) == ("gemini", "gemma-4-31b-it")
    assert (critic.llm_provider.provider, critic.llm_provider.model) == ("gemini", "gemini-3.8-flash")
    assert (critic.image_llm_provider.provider, critic.image_llm_provider.model) == ("gemini", "gemini-3.5-flash-lite")


def test_the_key_comes_from_secrets_and_no_other_provider_is_configured():
    env = pipeline_env()

    assert env["GEMINI_API_KEY"] == "${{ secrets.GEMINI_API_KEY }}"
    assert not [name for name in env if name.endswith("_API_KEY") and name != "GEMINI_API_KEY"]


def test_the_schedule_stays_off():
    assert not re.search(r"^\s*schedule:", WORKFLOW.read_text(), re.M)
