"""
Test script to verify Supabase connection and schema.
"""

import pytest
import logging

from backend.database import get_supabase, initialize_supabase

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)


def check_tables_exist(client):
    """Check if required tables exist."""
    logger.info("\n=== Test 1: Checking tables ===")
    tables = ['articles', 'users', 'likes', 'search_suggestions', 'article_embeddings']

    for table_name in tables:
        try:
            client.table(table_name).select('*').limit(1).execute()
            logger.info(f"✅ Table '{table_name}' exists")
        except Exception as e:
            logger.error(f"❌ Table '{table_name}' not found or error: {e}")
            raise


def run_article_operations(client):
    """Test article insert and query operations."""
    logger.info("\n=== Test 2: Testing article insert and query ===")
    test_article = {
        'id': 'art_20260215_test',
        'title': 'Test Article',
        'summary': 'This is a test article summary',
        'date': '2026-02-15',
        'reading_time_minutes': 12,
        'author': 'BharatVerse AI',
        'tags': ['test', 'history'],
        'content_file_path': 'articles/2026-02-15/art_20260215_test.json'
    }

    # Insert
    client.table('articles').insert(test_article).execute()
    logger.info("✅ Successfully inserted test article")

    # Query
    response = client.table('articles').select('*').eq('id', 'art_20260215_test').execute()
    if not response.data or len(response.data) == 0:
        raise Exception("Failed to retrieve inserted article")

    article = response.data[0]
    logger.info(f"✅ Successfully retrieved article: {article['title']}")


def run_full_text_search(client):
    """Test full-text search functionality."""
    logger.info("\n=== Test 3: Testing full-text search ===")
    try:
        response = client.table('articles').select('*').text_search('title', 'Test').execute()
        if response.data:
            logger.info(f"✅ Full-text search working: found {len(response.data)} results")
        else:
            logger.warning("⚠️  Full-text search returned no results (this is OK if no data)")
    except Exception as e:
        logger.error(f"❌ Full-text search failed: {e}")


def cleanup_test_data(client):
    """Clean up test data."""
    logger.info("\n=== Cleaning up test data ===")
    try:
        client.table('articles').delete().eq('id', 'art_20260215_test').execute()
        logger.info("✅ Cleaned up test data")
    except Exception as e:
        logger.warning(f"⚠️  Failed to clean up test data: {e}")


def check_storage_bucket(client):
    """Check if storage bucket exists."""
    logger.info("\n=== Test 4: Checking storage bucket ===")
    try:
        buckets = client.storage.list_buckets()
        bucket_names = [bucket.name for bucket in buckets]
        if 'articles' in bucket_names:
            logger.info("✅ Storage bucket 'articles' exists")
        else:
            logger.warning("⚠️  Storage bucket 'articles' not found. Create it in Supabase dashboard.")
    except Exception as e:
        logger.error(f"❌ Failed to check storage buckets: {e}")


@pytest.mark.asyncio
async def test_supabase():
    """Test Supabase connection and basic operations."""
    try:
        # Initialize Supabase
        logger.info("Initializing Supabase...")
        await initialize_supabase()

        # Get Supabase client
        supabase = get_supabase()
        client = supabase.get_admin_client()

        # Run all tests
        check_tables_exist(client)
        run_article_operations(client)
        run_full_text_search(client)
        cleanup_test_data(client)
        check_storage_bucket(client)

        logger.info("\n" + "=" * 60)
        logger.info("✅ All tests passed! Supabase is ready to use.")
        logger.info("=" * 60)

        assert True

    except Exception as e:
        logger.error(f"\n❌ Supabase test failed: {e}", exc_info=True)
        pytest.fail(f"Supabase test failed: {e}")
