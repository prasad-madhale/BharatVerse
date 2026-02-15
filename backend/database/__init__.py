"""
Database module for BharatVerse MVP.

Provides Supabase client for PostgreSQL database and storage operations.
"""

from backend.database.supabase_client import (
    SupabaseClient,
    get_supabase,
    initialize_supabase,
)

__all__ = [
    "SupabaseClient",
    "get_supabase",
    "initialize_supabase",
]
