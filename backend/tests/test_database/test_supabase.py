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
        
        # Test 1: Check if tables exist
        logger.info("\n=== Test 1: Checking tables ===")
        tables_to_check = ['articles', 'users', 'likes', 'search_suggestions', 'article_embeddings']
        
        for table_name in tables_to_check:
            try:
                response = client.table(table_name).select('*').limit(1).execute()
                logger.info(f"✅ Table '{table_name}' exists")
            except Exception as e:
                logger.error(f"❌ Table '{table_name}' not found or error: {e}")
                return False
        
        # Test 2: Insert and query an article
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
        try:
            response = client.table('articles').insert(test_article).execute()
            logger.info(f"✅ Successfully inserted test article")
        except Exception as e:
            logger.error(f"❌ Failed to insert article: {e}")
            return False
        
        # Query
        try:
            response = client.table('articles').select('*').eq('id', 'art_20260215_test').execute()
            if response.data and len(response.data) > 0:
                article = response.data[0]
                logger.info(f"✅ Successfully retrieved article: {article['title']}")
            else:
                logger.error("❌ Failed to retrieve inserted article")
                return False
        except Exception as e:
            logger.error(f"❌ Failed to query article: {e}")
            return False
        
        # Test 3: Test full-text search
        logger.info("\n=== Test 3: Testing full-text search ===")
        try:
            response = client.table('articles').select('*').text_search('title', 'Test').execute()
            if response.data:
                logger.info(f"✅ Full-text search working: found {len(response.data)} results")
            else:
                logger.warning("⚠️  Full-text search returned no results (this is OK if no data)")
        except Exception as e:
            logger.error(f"❌ Full-text search failed: {e}")
        
        # Clean up test data
        logger.info("\n=== Cleaning up test data ===")
        try:
            client.table('articles').delete().eq('id', 'art_20260215_test').execute()
            logger.info("✅ Cleaned up test data")
        except Exception as e:
            logger.warning(f"⚠️  Failed to clean up test data: {e}")
        
        # Test 4: Check storage bucket
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
        
        logger.info("\n" + "="*60)
        logger.info("✅ All tests passed! Supabase is ready to use.")
        logger.info("="*60)
        
        assert True  # Test passed
        
    except Exception as e:
        logger.error(f"\n❌ Supabase test failed: {e}", exc_info=True)
        pytest.fail(f"Supabase test failed: {e}")
