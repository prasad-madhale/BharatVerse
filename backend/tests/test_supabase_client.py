"""
Unit tests for SupabaseClient.

Tests client initialization and connection logic with mocked Supabase.
"""

import pytest
from unittest.mock import patch, MagicMock, AsyncMock
from backend.database.supabase_client import SupabaseClient, get_supabase


class TestSupabaseClientInitialization:
    """Test SupabaseClient initialization."""

    @patch('backend.database.supabase_client.get_settings')
    def test_client_initialization(self, mock_get_settings):
        """Test SupabaseClient initializes with correct settings."""
        mock_settings = MagicMock()
        mock_settings.supabase_url = "https://test.supabase.co"
        mock_settings.supabase_anon_key = "test-anon-key"
        mock_settings.supabase_service_role_key = "test-service-key"
        mock_get_settings.return_value = mock_settings

        client = SupabaseClient()

        assert client.url == "https://test.supabase.co"
        assert client.anon_key == "test-anon-key"
        assert client.service_role_key == "test-service-key"
        assert client._client is None
        assert client._admin_client is None

    @patch('backend.database.supabase_client.get_settings')
    @patch('backend.database.supabase_client.create_client')
    def test_get_client_lazy_initialization(self, mock_create_client, mock_get_settings):
        """Test get_client() lazy-loads the anon client."""
        mock_settings = MagicMock()
        mock_settings.supabase_url = "https://test.supabase.co"
        mock_settings.supabase_anon_key = "test-anon-key"
        mock_settings.supabase_service_role_key = "test-service-key"
        mock_get_settings.return_value = mock_settings

        mock_supabase_client = MagicMock()
        mock_create_client.return_value = mock_supabase_client

        client = SupabaseClient()
        result = client.get_client()

        mock_create_client.assert_called_once_with(
            "https://test.supabase.co",
            "test-anon-key"
        )
        assert result == mock_supabase_client
        assert client._client == mock_supabase_client

    @patch('backend.database.supabase_client.get_settings')
    @patch('backend.database.supabase_client.create_client')
    def test_get_client_returns_cached_instance(self, mock_create_client, mock_get_settings):
        """Test get_client() returns cached instance on subsequent calls."""
        mock_settings = MagicMock()
        mock_settings.supabase_url = "https://test.supabase.co"
        mock_settings.supabase_anon_key = "test-anon-key"
        mock_settings.supabase_service_role_key = "test-service-key"
        mock_get_settings.return_value = mock_settings

        mock_supabase_client = MagicMock()
        mock_create_client.return_value = mock_supabase_client

        client = SupabaseClient()
        result1 = client.get_client()
        result2 = client.get_client()

        # Should only call create_client once
        assert mock_create_client.call_count == 1
        assert result1 is result2

    @patch('backend.database.supabase_client.get_settings')
    @patch('backend.database.supabase_client.create_client')
    def test_get_admin_client_lazy_initialization(self, mock_create_client, mock_get_settings):
        """Test get_admin_client() lazy-loads the admin client."""
        mock_settings = MagicMock()
        mock_settings.supabase_url = "https://test.supabase.co"
        mock_settings.supabase_anon_key = "test-anon-key"
        mock_settings.supabase_service_role_key = "test-service-key"
        mock_get_settings.return_value = mock_settings

        mock_admin_client = MagicMock()
        mock_create_client.return_value = mock_admin_client

        client = SupabaseClient()
        result = client.get_admin_client()

        mock_create_client.assert_called_once_with(
            "https://test.supabase.co",
            "test-service-key"
        )
        assert result == mock_admin_client
        assert client._admin_client == mock_admin_client


class TestSupabaseClientConnection:
    """Test SupabaseClient connection testing."""

    @patch('backend.database.supabase_client.get_settings')
    @patch('backend.database.supabase_client.create_client')
    @pytest.mark.asyncio
    async def test_connection_success(self, mock_create_client, mock_get_settings):
        """Test test_connection() returns True on successful connection."""
        mock_settings = MagicMock()
        mock_settings.supabase_url = "https://test.supabase.co"
        mock_settings.supabase_anon_key = "test-anon-key"
        mock_settings.supabase_service_role_key = "test-service-key"
        mock_get_settings.return_value = mock_settings

        # Mock successful query
        mock_response = MagicMock()
        mock_table = MagicMock()
        mock_table.select.return_value.limit.return_value.execute.return_value = mock_response
        mock_admin_client = MagicMock()
        mock_admin_client.table.return_value = mock_table
        mock_create_client.return_value = mock_admin_client

        client = SupabaseClient()
        result = await client.test_connection()

        assert result is True
        mock_admin_client.table.assert_called_once_with('articles')

    @patch('backend.database.supabase_client.get_settings')
    @patch('backend.database.supabase_client.create_client')
    @pytest.mark.asyncio
    async def test_connection_failure(self, mock_create_client, mock_get_settings):
        """Test test_connection() returns False on connection failure."""
        mock_settings = MagicMock()
        mock_settings.supabase_url = "https://test.supabase.co"
        mock_settings.supabase_anon_key = "test-anon-key"
        mock_settings.supabase_service_role_key = "test-service-key"
        mock_get_settings.return_value = mock_settings

        # Mock failed query
        mock_admin_client = MagicMock()
        mock_admin_client.table.side_effect = Exception("Connection failed")
        mock_create_client.return_value = mock_admin_client

        client = SupabaseClient()
        result = await client.test_connection()

        assert result is False


class TestGetSupabase:
    """Test get_supabase() singleton behavior."""

    @patch('backend.database.supabase_client.get_settings')
    def test_get_supabase_singleton(self, mock_get_settings):
        """Test get_supabase() returns same instance."""
        # Reset global state
        import backend.database.supabase_client
        backend.database.supabase_client._supabase_client = None

        mock_settings = MagicMock()
        mock_settings.supabase_url = "https://test.supabase.co"
        mock_settings.supabase_anon_key = "test-anon-key"
        mock_settings.supabase_service_role_key = "test-service-key"
        mock_get_settings.return_value = mock_settings

        client1 = get_supabase()
        client2 = get_supabase()

        assert client1 is client2
