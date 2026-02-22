"""
Property-based tests for article persistence.

Tests Property 5: Article persistence round-trip
"""

import pytest
from hypothesis import given, strategies as st, settings
from datetime import date
import uuid

from backend.database import get_supabase


# Hypothesis strategies for generating test data
@st.composite
def article_strategy(draw):
    """Generate random valid article data for property testing."""
    article_id = (
        f"art_{draw(st.integers(min_value=20200101, max_value=20301231))}_"
        f"{draw(st.integers(min_value=1, max_value=999)):03d}"
    )

    # Use printable ASCII characters to avoid null bytes and other problematic characters
    safe_text_title = st.text(
        alphabet=st.characters(min_codepoint=32, max_codepoint=126),
        min_size=10,
        max_size=200
    )

    safe_text_summary = st.text(
        alphabet=st.characters(min_codepoint=32, max_codepoint=126),
        min_size=50,
        max_size=500
    )

    # Use only alphanumeric characters for tags to avoid filtering
    safe_text_tag = st.text(
        alphabet='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        min_size=3,
        max_size=20
    )

    return {
        'id': article_id,
        'title': draw(safe_text_title),
        'summary': draw(safe_text_summary),
        'date': draw(st.dates(
            min_value=date(2020, 1, 1),
            max_value=date(2030, 12, 31)
        )).isoformat(),
        'reading_time_minutes': draw(st.integers(min_value=5, max_value=30)),
        'author': draw(st.sampled_from([
            'BharatVerse AI', 'Historical AI', 'Content Generator'
        ])),
        'tags': draw(st.lists(safe_text_tag, min_size=1, max_size=5)),
        'content_file_path': (
            f"articles/"
            f"{draw(st.dates(min_value=date(2020, 1, 1), max_value=date(2030, 12, 31))).isoformat()}/"
            f"{article_id}.json"
        )
    }


@pytest.mark.asyncio
@pytest.mark.property
@given(article_data=article_strategy())
@settings(deadline=1000)  # 1 second deadline for network requests
async def test_article_persistence_round_trip(article_data):
    """
    Feature: bharatverse-mvp, Property 5: Article persistence round-trip

    For any valid generated article, storing it and then retrieving it by ID
    should return an equivalent article with all fields preserved.

    Validates: Requirements 3.1, 3.3
    """
    supabase = get_supabase()
    client = supabase.get_admin_client()

    article_id = article_data['id']

    try:
        # Store article
        insert_response = client.table('articles').insert(article_data).execute()
        assert insert_response.data is not None, "Insert should return data"
        assert len(insert_response.data) > 0, "Insert should return at least one record"

        # Retrieve article by ID
        select_response = client.table('articles').select('*').eq('id', article_id).execute()
        assert select_response.data is not None, "Select should return data"
        assert len(select_response.data) > 0, "Select should return at least one record"

        retrieved = select_response.data[0]

        # Assert all fields are preserved
        assert retrieved['id'] == article_data['id'], "ID should be preserved"
        assert retrieved['title'] == article_data['title'], "Title should be preserved"
        assert retrieved['summary'] == article_data['summary'], "Summary should be preserved"
        assert retrieved['date'] == article_data['date'], "Date should be preserved"
        assert retrieved['reading_time_minutes'] == article_data['reading_time_minutes'], "Reading time should be preserved"
        assert retrieved['author'] == article_data['author'], "Author should be preserved"
        assert retrieved['tags'] == article_data['tags'], "Tags should be preserved"
        assert retrieved['content_file_path'] == article_data['content_file_path'], "Content file path should be preserved"

        # Verify timestamps were auto-generated
        assert retrieved['created_at'] is not None, "created_at should be auto-generated"
        assert retrieved['updated_at'] is not None, "updated_at should be auto-generated"

    finally:
        # Cleanup: Delete test article
        try:
            client.table('articles').delete().eq('id', article_id).execute()
        except Exception:
            pass  # Ignore cleanup errors


@pytest.mark.asyncio
@pytest.mark.property
async def test_article_persistence_with_optional_fields():
    """
    Feature: bharatverse-mvp, Property 5: Article persistence round-trip (with optional fields)

    Test that optional fields (image_url) are also preserved correctly.

    Validates: Requirements 3.1, 3.3
    """
    supabase = get_supabase()
    client = supabase.get_admin_client()

    article_id = f"art_test_{uuid.uuid4().hex[:8]}"

    article_data = {
        'id': article_id,
        'title': 'Test Article with Image',
        'summary': 'This is a test article with an image URL',
        'date': '2026-02-15',
        'reading_time_minutes': 12,
        'author': 'BharatVerse AI',
        'tags': ['test', 'image'],
        'image_url': 'https://example.com/images/test.jpg',
        'content_file_path': f'articles/2026-02-15/{article_id}.json'
    }

    try:
        # Store article
        insert_response = client.table('articles').insert(article_data).execute()
        assert insert_response.data is not None

        # Retrieve article
        select_response = client.table('articles').select('*').eq('id', article_id).execute()
        retrieved = select_response.data[0]

        # Assert optional field is preserved
        assert retrieved['image_url'] == article_data['image_url'], "Image URL should be preserved"

    finally:
        # Cleanup
        try:
            client.table('articles').delete().eq('id', article_id).execute()
        except Exception:
            pass


@pytest.mark.asyncio
@pytest.mark.property
async def test_article_persistence_null_optional_fields():
    """
    Feature: bharatverse-mvp, Property 5: Article persistence round-trip (null optional fields)

    Test that articles without optional fields can be stored and retrieved.

    Validates: Requirements 3.1, 3.3
    """
    supabase = get_supabase()
    client = supabase.get_admin_client()

    article_id = f"art_test_{uuid.uuid4().hex[:8]}"

    article_data = {
        'id': article_id,
        'title': 'Test Article without Image',
        'summary': 'This is a test article without an image URL',
        'date': '2026-02-15',
        'reading_time_minutes': 10,
        'author': 'BharatVerse AI',
        'tags': ['test'],
        'content_file_path': f'articles/2026-02-15/{article_id}.json'
        # Note: image_url is omitted (NULL)
    }

    try:
        # Store article
        insert_response = client.table('articles').insert(article_data).execute()
        assert insert_response.data is not None

        # Retrieve article
        select_response = client.table('articles').select('*').eq('id', article_id).execute()
        retrieved = select_response.data[0]

        # Assert optional field is NULL
        assert retrieved['image_url'] is None, "Image URL should be NULL when not provided"

        # Assert required fields are still preserved
        assert retrieved['title'] == article_data['title']
        assert retrieved['summary'] == article_data['summary']

    finally:
        # Cleanup
        try:
            client.table('articles').delete().eq('id', article_id).execute()
        except Exception:
            pass
