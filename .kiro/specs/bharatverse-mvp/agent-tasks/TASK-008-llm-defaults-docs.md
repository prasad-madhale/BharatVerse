---
id: TASK-008
title: Correct the documented LLM provider and model defaults
depends_on: 
requires: 
allowed: .env.example, .kiro/specs/bharatverse-mvp/roadmap.md
verify: cd "$BV_ROOT" && ! grep -q 'claude-3-haiku' .env.example
verify: cd "$BV_ROOT" && ! grep -q 'gemini-1.5-flash' .env.example
verify: cd "$BV_ROOT" && ! grep -q 'llama-3.1-70b' .env.example
verify: cd "$BV_ROOT" && grep -q 'gemini-2.5-flash' .env.example
verify: cd "$BV_ROOT" && grep -q 'claude-sonnet-5' .env.example
verify: cd "$BV_ROOT" && grep -q 'llama-3.3-70b-versatile' .env.example
verify: cd "$BV_ROOT" && ! grep -q 'Default provider is now' .kiro/specs/bharatverse-mvp/roadmap.md
verify: cd "$BV_ROOT" && grep -q 'still defaults to .gemini.' .kiro/specs/bharatverse-mvp/roadmap.md
commit: docs: correct the documented LLM provider and model defaults
---

# TASK-008: Correct the documented LLM provider and model defaults

## Why

Two documents disagree with the code.

- `.env.example` lists model names that are retired or no longer the default (`gemini-1.5-flash`,
  `claude-3-haiku-20240307`, `llama-3.1-70b-versatile`). The real defaults are in `common/llm_provider.py`.
- The roadmap says the default provider is now Claude. It is not. `common/config.py` still defaults to `gemini`. Only
  the daily GitHub Actions workflow selects `anthropic`, by setting `LLM_PROVIDER` explicitly.

This task records the truth. It does **not** change the default provider: doing so changes what the next pipeline run
costs, so that is a person's decision.

## Read first, and nothing else

- `.env.example`

## Steps

### Step 1. Correct both documents

Run this script exactly as written. It stops without writing anything if an anchor is missing or repeated.

<!-- step: run -->
```bash
cd "$BV_ROOT" && python - <<'PY'
from pathlib import Path


def replace_once(text, old, new):
    assert text.count(old) == 1, f"text not unique or missing: {old!r}"
    return text.replace(old, new)


# 1. .env.example: current default model names, and which provider each entry point uses.
env_path = Path(".env.example")
env = env_path.read_text()
env = replace_once(
    env,
    "# LLM Provider (choose one: gemini, anthropic, openai, groq)\n",
    "# LLM Provider (choose one: gemini, anthropic, openai, groq)\n"
    "# A local run without LLM_PROVIDER uses gemini. The daily GitHub Actions pipeline sets\n"
    "# LLM_PROVIDER=anthropic explicitly.\n",
)
env = replace_once(
    env,
    "# LLM_MODEL=gemini-1.5-flash  # For Gemini\n"
    "# LLM_MODEL=claude-3-haiku-20240307  # For Anthropic\n"
    "# LLM_MODEL=gpt-3.5-turbo  # For OpenAI\n"
    "# LLM_MODEL=llama-3.1-70b-versatile  # For Groq\n",
    "# These are the defaults used when LLM_MODEL is unset (see common/llm_provider.py):\n"
    "# LLM_MODEL=gemini-2.5-flash  # For Gemini\n"
    "# LLM_MODEL=claude-sonnet-5  # For Anthropic\n"
    "# LLM_MODEL=gpt-3.5-turbo  # For OpenAI\n"
    "# LLM_MODEL=llama-3.3-70b-versatile  # For Groq\n",
)
env_path.write_text(env)

# 2. roadmap.md: correct the claim about the default provider.
roadmap_path = Path(".kiro/specs/bharatverse-mvp/roadmap.md")
roadmap = roadmap_path.read_text()
roadmap = replace_once(
    roadmap,
    "Default provider is now **Claude Sonnet 5** (switched from Gemini after its free daily quota ran out mid-testing;",
    "The Anthropic provider's default model is **Claude Sonnet 5**, which the daily workflow selects explicitly "
    "with `LLM_PROVIDER=anthropic`. `common/config.py` itself still defaults to `gemini`, so a local run without "
    "`LLM_PROVIDER` uses Gemini (the pipeline moved to Claude after Gemini's free daily quota ran out mid-testing;",
)
roadmap_path.write_text(roadmap)
print(".env.example and roadmap.md updated")
PY
```

## Verify

Run every `verify:` command from the front matter, from the repository root, and make each one exit 0.
If the formatting check prints a diff, run `python -m autopep8 --in-place --aggressive --aggressive
--max-line-length=127 <each file you changed>` and run the check again. Do not edit any file that is not listed
under `allowed`.

## Definition of done

- Every step above was applied exactly as written.
- Every `verify:` command exits 0.
- Only files listed under `allowed` changed.
- You did not run git commit, checkout, reset, or push. The runner commits.

## Out of scope

Do not change `common/config.py`, `common/llm_provider.py`, or any workflow file.
