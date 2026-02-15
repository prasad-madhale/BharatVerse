"""
Supabase client for BharatVerse MVP.

Provides connection to Supabase PostgreSQL database and storage.
"""

from supabase import create_client, Client
from typing import Optional
import logging

from backend.config import get_settings

logger = logging.getLogger(__name__)


class SupabaseClient:
    """
    Supabase client wrapper for database and storage operations.
    """
    
    def __init__(self):
        """Initialize Supabase client."""
        settings = get_settings()
        
        self.url = settings.supabase_url
        self.anon_key = settings.supabase_anon_key
        self.service_role_key = settings.supabase_service_role_key
        
        # Client for public operations (uses anon key)
        self._client: Optional[Client] = None
        
        # Client for admin operations (uses service role key)
        self._admin_client: Optional[Client] = None
    
    def get_client(self) -> Client:
        """
        Get Supabase client for public operations.
        
        Returns:
            Client: Supabase client with anon key
        """
        if self._client is None:
            self._client = create_client(self.url, self.anon_key)
            logger.info("Initialized Supabase client (anon)")
        return self._client
    
    def get_admin_client(self) -> Client:
        """
        Get Supabase client for admin operations.
        
        Uses service role key which bypasses Row Level Security.
        Use this for backend operations that need full database access.
        
        Returns:
            Client: Supabase client with service role key
        """
        if self._admin_client is None:
            self._admin_client = create_client(self.url, self.service_role_key)
            logger.info("Initialized Supabase admin client (service role)")
        return self._admin_client
    
    async def test_connection(self) -> bool:
        """
        Test database connection.
        
        Returns:
            bool: True if connection successful
        """
        try:
            client = self.get_admin_client()
            # Try a simple query
            response = client.table('articles').select('id').limit(1).execute()
            logger.info("✅ Supabase connection successful")
            return True
        except Exception as e:
            logger.error(f"❌ Supabase connection failed: {e}")
            return False


# Global Supabase client instance
_supabase_client: Optional[SupabaseClient] = None


def get_supabase() -> SupabaseClient:
    """
    Get global Supabase client instance (singleton pattern).
    
    Returns:
        SupabaseClient: Supabase client instance
    """
    global _supabase_client
    if _supabase_client is None:
        _supabase_client = SupabaseClient()
    return _supabase_client


async def initialize_supabase():
    """
    Initialize Supabase client and test connection.
    
    Convenience function for application startup.
    """
    supabase = get_supabase()
    await supabase.test_connection()
