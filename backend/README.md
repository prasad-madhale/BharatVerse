# BharatVerse Backend API

FastAPI-based REST API for the BharatVerse mobile application.

## Overview

The backend provides:
- REST API endpoints for articles, search, authentication, and likes
- Supabase PostgreSQL database with full-text search and pgvector
- User authentication via Supabase Auth (email/password + OAuth)
- Article search with autocomplete and semantic similarity
- Rate limiting and security features

## Prerequisites

- Python 3.12+
- Virtual environment activated
- Environment variables configured

## Setup

### 1. Verify Python Version

```bash
python3 --version  # Must be 3.12.0 or higher
```

If you have an older version, see the [main README](../README.md#python-setup) for installation instructions.

### 2. Create Virtual Environment

From the project root:

```bash
# Use Python 3.12 explicitly
python3.12 -m venv .venv
# OR if using pyenv: python -m venv .venv

source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Verify Python version
python --version  # Should show 3.12+
```

### 3. Install Dependencies

```bash
pip install -r backend/requirements.txt
```

### 3. Configure Environment Variables

Create a `.env` file in the project root with:

```env
# Required - Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key_here
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key_here

# Required - LLM Provider
LLM_PROVIDER=gemini  # Options: gemini (FREE), anthropic, openai, groq

# Required - API Key (choose based on provider)
GEMINI_API_KEY=your_gemini_api_key_here  # Get from: https://makersuite.google.com/app/apikey

# Optional (for OAuth - configured in Supabase dashboard)
# GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET configured in Supabase
# FACEBOOK_APP_ID and FACEBOOK_APP_SECRET configured in Supabase

# Optional (defaults provided)
API_HOST=0.0.0.0
API_PORT=8000
DEBUG=false
```

See `.env.example` for a complete template.

### 4. Set Up Supabase Database

1. **Create Supabase Project**:
   - Go to https://supabase.com and create a new project
   - Note your project URL and API keys from Settings > API

2. **Deploy Database Schema**:
   - Open the SQL Editor in your Supabase dashboard
   - Copy the contents of `backend/database/schema.sql`
   - Execute the SQL to create all tables, indexes, and triggers

3. **Create Storage Bucket**:
   - Go to Storage in Supabase dashboard
   - Create a new bucket named `articles`
   - Set it to public for read access

4. **Verify Setup**:
   ```bash
   python backend/database/test_supabase.py
   ```
   
   This will verify:
   - Connection to Supabase
   - All tables exist
   - Insert/query operations work
   - Full-text search is functional
   - Storage bucket is accessible

## Running the API

### Development Mode

```bash
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```

The API will be available at:
- **API**: http://localhost:8000
- **Interactive docs**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

### Production Mode

```bash
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --workers 4
```

## Project Structure

```
backend/
├── api/                # API routers and endpoints
│   ├── articles.py     # Article endpoints
│   ├── auth.py         # Authentication endpoints
│   ├── search.py       # Search endpoints
│   └── likes.py        # Like endpoints
├── services/           # Business logic
│   ├── article_service.py
│   ├── auth_service.py
│   ├── search_service.py
│   └── like_service.py
├── models/             # Data models and schemas
│   ├── article.py
│   ├── user.py
│   └── schemas.py
├── database/           # Database operations
│   ├── __init__.py
│   ├── schema.sql          # PostgreSQL schema for Supabase
│   ├── supabase_client.py  # Supabase client wrapper
│   └── test_supabase.py    # Connection verification script
├── utils/              # Utility functions
│   ├── llm_provider.py # Unified LLM interface
│   └── validators.py
├── tests/              # Test suite
│   ├── conftest.py         # Shared pytest fixtures
│   ├── test_database/      # Database tests
│   │   ├── test_supabase.py
│   │   └── test_article_persistence.py
│   ├── test_api/           # API endpoint tests
│   ├── test_services/      # Service layer tests
│   ├── test_utils/         # Utility function tests
│   └── integration/        # End-to-end tests
├── config.py           # Configuration management
├── main.py             # FastAPI application entry point
├── pytest.ini          # Pytest configuration
├── requirements.txt    # Python dependencies
└── README.md           # This file
```

## API Endpoints

### Articles

- `GET /api/v1/articles/daily` - Get today's daily article
- `GET /api/v1/articles/{id}` - Get article by ID
- `GET /api/v1/articles` - List articles (paginated)
- `GET /api/v1/articles/search?q=...` - Search articles

### Search

- `GET /api/v1/articles/search/autocomplete?q=...` - Get autocomplete suggestions
- `GET /api/v1/articles/search/semantic?q=...` - Semantic similarity search

### Authentication

- `POST /api/v1/auth/register` - Register with email/password
- `POST /api/v1/auth/login` - Login with email/password
- `POST /api/v1/auth/oauth/google` - OAuth login with Google
- `POST /api/v1/auth/oauth/facebook` - OAuth login with Facebook
- `POST /api/v1/auth/refresh` - Refresh access token
- `POST /api/v1/auth/logout` - Logout user

### Likes (Authenticated)

- `POST /api/v1/articles/{id}/like` - Like an article
- `DELETE /api/v1/articles/{id}/like` - Unlike an article
- `GET /api/v1/users/me/likes` - Get user's liked articles

## Testing

The backend uses pytest for testing with support for async tests, property-based tests, and integration tests.

### Test Structure

Tests are organized in `backend/tests/` mirroring the source code structure:

```
backend/tests/
├── conftest.py                      # Shared pytest fixtures
├── test_database/                   # Database and Supabase tests
│   ├── test_supabase.py            # Connection and basic operations
│   └── test_article_persistence.py # Property-based persistence tests
├── test_api/                        # API endpoint tests
├── test_services/                   # Service layer tests
├── test_utils/                      # Utility function tests
└── integration/                     # End-to-end integration tests
```

### Running Tests

**Run all tests:**
```bash
pytest backend/tests/
```

**Run specific test file:**
```bash
pytest backend/tests/test_database/test_article_persistence.py
```

**Run specific test directory:**
```bash
pytest backend/tests/test_database/
```

**Run with verbose output:**
```bash
pytest backend/tests/ -v
```

**Run with live logs (useful for debugging):**
```bash
pytest backend/tests/ -s
```

**Run quietly (less output):**
```bash
pytest backend/tests/ -q
```

### Test Types

**Unit tests** - Test individual functions and classes:
```bash
pytest backend/tests/ -m unit
```

**Integration tests** - Test end-to-end flows:
```bash
pytest backend/tests/integration/
```

**Property-based tests** - Test universal properties with Hypothesis (100+ iterations):
```bash
pytest backend/tests/ -m property
```

Property-based tests use Hypothesis to generate random test data and verify correctness properties hold across diverse inputs. Example: `test_article_persistence_round_trip` runs 100 iterations with different article data to ensure persistence works correctly.

### Coverage Reports

**Run tests with coverage:**
```bash
pytest backend/tests/ --cov=backend --cov-report=term
```

**Generate HTML coverage report:**
```bash
pytest backend/tests/ --cov=backend --cov-report=html
open htmlcov/index.html  # View in browser
```

**Coverage with missing lines:**
```bash
pytest backend/tests/ --cov=backend --cov-report=term-missing
```

### Test Configuration

Test configuration is in `backend/pytest.ini`:
- Async tests run automatically with `asyncio_mode = auto`
- Test discovery pattern: `test_*.py`
- Logs displayed during test runs
- Custom markers for test categorization

### Writing Tests

**Async test example:**
```python
import pytest

@pytest.mark.asyncio
async def test_supabase_connection(supabase_client):
    """Test Supabase connection."""
    client = supabase_client.get_admin_client()
    response = client.table('articles').select('*').limit(1).execute()
    assert response is not None
```

**Property-based test example:**
```python
import pytest
from hypothesis import given, strategies as st

@pytest.mark.asyncio
@pytest.mark.property
@given(article_data=article_strategy())
async def test_article_persistence_round_trip(article_data):
    """Test that articles can be stored and retrieved correctly."""
    supabase = get_supabase()
    client = supabase.get_admin_client()
    
    # Store article
    insert_response = client.table('articles').insert(article_data).execute()
    assert insert_response.data is not None
    
    # Retrieve article
    select_response = client.table('articles').select('*').eq('id', article_data['id']).execute()
    retrieved = select_response.data[0]
    
    # Verify all fields preserved
    assert retrieved['title'] == article_data['title']
    assert retrieved['summary'] == article_data['summary']
    # ... more assertions
```

**Using fixtures:**
```python
@pytest.mark.asyncio
async def test_article_insert(supabase_client, clean_test_data):
    """Test article insertion with automatic cleanup."""
    client = supabase_client.get_admin_client()
    
    test_article = {
        'id': 'test_article_001',
        'title': 'Test Article',
        # ... other fields
    }
    
    # Track for cleanup
    clean_test_data['article_ids'].append('test_article_001')
    
    # Test insertion
    response = client.table('articles').insert(test_article).execute()
    assert response.data is not None
    # Cleanup happens automatically after test
```

### Continuous Integration

Tests run automatically on:
- Pull requests
- Commits to main branch
- Scheduled daily runs

CI configuration in `.github/workflows/test.yml`

## Database

### Supabase PostgreSQL

The backend uses Supabase (managed PostgreSQL) with the following features:

**Tables:**
- `articles` - Article metadata with JSONB content and tsvector for full-text search
- `users` - User profiles (extends Supabase auth.users)
- `likes` - Article likes with Row-Level Security
- `search_suggestions` - Autocomplete suggestions
- `article_embeddings` - Semantic search embeddings (TEXT format, pgvector optional)

**Features:**
- Full-text search using PostgreSQL tsvector and ts_rank
- Automatic tsvector updates via triggers
- Row-Level Security (RLS) for user data isolation
- Supabase Auth for authentication
- Supabase Storage for article images

### Schema Management

The database schema is defined in `backend/database/schema.sql`. To update:

1. Modify `schema.sql`
2. Run the updated SQL in Supabase SQL Editor
3. Test with `python backend/database/test_supabase.py`

### Backup Database

Supabase provides automatic backups. To create manual backup:

1. Go to Supabase Dashboard > Database > Backups
2. Click "Create Backup"
3. Download backup file if needed

## Development

### Code Style

Follow PEP 8 conventions:
- Use `snake_case` for functions and variables
- Use `CamelCase` for classes
- Maximum line length: 100 characters
- Use type hints for all functions

### Adding New Endpoints

1. Create router in `backend/api/`
2. Implement service logic in `backend/services/`
3. Add data models in `backend/models/`
4. Write tests in `tests/`
5. Update API documentation

### Environment Variables

All configuration is managed through `backend/config.py` using pydantic-settings. Add new settings to the `Settings` class.

## Deployment

### Docker

```bash
# Build image
docker build -t bharatverse-backend -f backend/Dockerfile .

# Run container
docker run -p 8000:8000 --env-file .env bharatverse-backend
```

### Docker Compose

```bash
docker-compose up -d
```

### Manual Deployment

1. Set up Python 3.12+ on server
2. Clone repository
3. Install dependencies: `pip install -r backend/requirements.txt`
4. Configure environment variables (Supabase URL and keys)
5. Verify Supabase connection: `python backend/database/test_supabase.py`
6. Run with gunicorn: `gunicorn backend.main:app -w 4 -k uvicorn.workers.UvicornWorker`
7. Set up nginx as reverse proxy
8. Configure SSL with Let's Encrypt

### Supabase Configuration

Ensure your Supabase project has:
- Database schema deployed from `backend/database/schema.sql`
- Storage bucket `articles` created and configured
- OAuth providers enabled (if using Google/Facebook login)
- Row-Level Security policies active

## Monitoring

### Logs

Logs are written to stdout in JSON format. Configure log aggregation with:
- CloudWatch (AWS)
- Stackdriver (GCP)
- ELK Stack (self-hosted)

### Health Check

```bash
curl http://localhost:8000/health
```

### Metrics

API metrics available at:
- Request count
- Response times
- Error rates
- Active users

## Troubleshooting

### Supabase Connection Errors

```bash
# Verify environment variables
cat .env | grep SUPABASE

# Test connection
python backend/database/test_supabase.py

# Check Supabase project status in dashboard
```

### Import Errors

```bash
# Ensure virtual environment is activated
source .venv/bin/activate

# Reinstall dependencies
pip install -r backend/requirements.txt
```

### Port Already in Use

```bash
# Find process using port 8000
lsof -i :8000

# Kill process
kill -9 <PID>
```

### Test Failures

```bash
# Run tests with verbose output
pytest backend/tests/ -v -s

# Check Supabase connection
python backend/database/test_supabase.py

# Verify .env file has correct Supabase credentials
```

## Performance

### Optimization Tips

1. **Database**: Supabase handles indexing automatically, but verify indexes exist for frequently queried fields
2. **Caching**: Use Redis for session storage and API caching
3. **Connection Pooling**: Supabase client handles connection pooling automatically
4. **Rate Limiting**: Adjust limits based on traffic patterns
5. **Async Operations**: Use async/await for I/O operations

### Benchmarking

```bash
# Install wrk
brew install wrk  # macOS
apt-get install wrk  # Ubuntu

# Benchmark API
wrk -t4 -c100 -d30s http://localhost:8000/api/v1/articles/daily
```

## Security

- All passwords hashed by Supabase Auth (bcrypt)
- JWT tokens managed by Supabase Auth (short expiration)
- Row-Level Security (RLS) enforces data access control
- HTTPS only in production
- Input validation on all endpoints
- SQL injection prevention (Supabase client uses parameterized queries)
- Rate limiting (100 requests/minute per IP)
- CORS configured for mobile app origins only

## Support

For issues or questions:
1. Check the [design document](../.kiro/specs/bharatverse-mvp/design.md)
2. Review [AGENTS.md](../.kiro/AGENTS.md) for development guidelines
3. Check existing issues in the repository
