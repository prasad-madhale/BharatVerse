"""
Shared pytest fixtures and configuration for BharatVerse backend tests.

This file is automatically loaded by pytest and provides fixtures
that can be used across all test modules.
"""

import pytest
import os

# backend.main builds the FastAPI app at module level, which calls
# get_settings() on import -- so merely importing it (e.g. in
# test_api/test_articles.py) requires Supabase credentials to be present,
# even for tests that never touch Supabase. Locally this is masked by a
# real .env file with real credentials; CI has no .env at all. Setting
# harmless placeholders here (before any test module is collected, since
# conftest.py is always imported first) makes collection succeed
# regardless. Integration tests below override these with real values
# loaded from .env.
os.environ.setdefault('SUPABASE_URL', 'https://test.supabase.co')
os.environ.setdefault('SUPABASE_ANON_KEY', 'test-anon-key')
os.environ.setdefault('SUPABASE_SERVICE_ROLE_KEY', 'test-service-role-key')

from backend.database import get_supabase, initialize_supabase
import backend.config as config_module
import backend.database.supabase_client as supabase_module


@pytest.fixture(scope="function", autouse=True)
def reset_singletons(request):
    """
    Reset global singletons before each test.

    For integration tests, also force reload .env file.
    """
    # Check if this is an integration test
    is_integration = 'integration' in [mark.name for mark in request.node.iter_markers()]

    if is_integration:
        # Force reload from .env file for integration tests
        from dotenv import load_dotenv

        # Clear any test environment variables
        test_vars = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'JWT_SECRET_KEY']
        for var in test_vars:
            if var in os.environ:
                del os.environ[var]

        # Force reload from .env file
        load_dotenv('../.env', override=True)

    # Reset settings singleton
    config_module._settings = None

    # Reset supabase singleton
    supabase_module._supabase_client = None

    yield

    # Cleanup singletons
    config_module._settings = None
    supabase_module._supabase_client = None


@pytest.fixture(scope="session")
async def supabase_client():
    """
    Provide a Supabase client for tests.

    Initializes connection once per test session.
    """
    await initialize_supabase()
    client = get_supabase()
    yield client
    # No cleanup needed - Supabase is cloud-hosted


@pytest.fixture
async def clean_test_data():
    """
    Clean up test data after each test.

    Usage:
        async def test_something(clean_test_data):
            # Test code here
            # Cleanup happens automatically after test
    """
    test_article_ids = []
    test_user_ids = []

    yield {
        'article_ids': test_article_ids,
        'user_ids': test_user_ids
    }

    # Cleanup after test
    supabase = get_supabase()
    client = supabase.get_admin_client()

    for article_id in test_article_ids:
        try:
            client.table('articles').delete().eq('id', article_id).execute()
        except Exception:
            pass  # Ignore cleanup errors

    for user_id in test_user_ids:
        try:
            client.table('users').delete().eq('id', user_id).execute()
        except Exception:
            pass  # Ignore cleanup errors
