"""
Shared pytest fixtures and configuration for BharatVerse backend tests.

This file is automatically loaded by pytest and provides fixtures
that can be used across all test modules.
"""

import pytest

from backend.database import get_supabase, initialize_supabase


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
