# BharatVerse Backend API

FastAPI-based REST API for the BharatVerse mobile application.

## Overview

The backend provides:
- REST API endpoints for articles, search, authentication, and likes
- SQLite database with FTS5 full-text search
- User authentication (email/password + OAuth)
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
# Required - LLM Provider
LLM_PROVIDER=gemini  # Options: gemini (FREE), anthropic, openai, groq

# Required - API Key (choose based on provider)
GEMINI_API_KEY=your_gemini_api_key_here  # Get from: https://makersuite.google.com/app/apikey

# Required - JWT Secret
JWT_SECRET_KEY=your_secret_key_here  # Generate with: openssl rand -hex 32

# Optional (for OAuth)
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret
FACEBOOK_APP_ID=your_facebook_app_id
FACEBOOK_APP_SECRET=your_facebook_app_secret

# Optional (defaults provided)
DATABASE_PATH=./bharatverse.db
ARTICLES_STORAGE_PATH=./articles
API_HOST=0.0.0.0
API_PORT=8000
DEBUG=false
```

### 4. Initialize Database

```bash
python backend/init_db.py
```

This creates the SQLite database with all required tables and indexes.

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
│   ├── connection.py
│   ├── migrations.py
│   └── queries.py
├── utils/              # Utility functions
│   ├── jwt.py
│   ├── password.py
│   └── validators.py
├── config.py           # Configuration management
├── main.py             # FastAPI application entry point
├── init_db.py          # Database initialization script
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

### Run All Tests

```bash
pytest
```

### Run with Coverage

```bash
pytest --cov=backend --cov-report=html
```

### Run Specific Test Types

```bash
# Unit tests only
pytest tests/unit/

# Integration tests only
pytest tests/integration/

# Property-based tests only
pytest -m property_test
```

### Run Tests in Watch Mode

```bash
pytest-watch
```

## Database

### Schema

The database uses SQLite with the following tables:

- `articles` - Article metadata
- `articles_fts` - Full-text search index (FTS5)
- `users` - User accounts
- `likes` - Article likes
- `search_suggestions` - Autocomplete suggestions
- `article_embeddings` - Semantic search embeddings

### Migrations

```bash
# Run migrations
python backend/database/migrations.py

# Create new migration
python backend/database/migrations.py create "migration_name"
```

### Backup Database

```bash
sqlite3 bharatverse.db ".backup bharatverse_backup.db"
```

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
4. Configure environment variables
5. Initialize database: `python backend/init_db.py`
6. Run with gunicorn: `gunicorn backend.main:app -w 4 -k uvicorn.workers.UvicornWorker`
7. Set up nginx as reverse proxy
8. Configure SSL with Let's Encrypt

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

### Database Locked Error

```bash
# Check for stale connections
lsof bharatverse.db

# Restart API server
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

## Performance

### Optimization Tips

1. **Database**: Add indexes for frequently queried fields
2. **Caching**: Use Redis for session storage and API caching
3. **Connection Pooling**: Configure SQLite connection pool
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

- All passwords hashed with bcrypt (cost factor 12)
- JWT tokens with short expiration (1 hour access, 30 days refresh)
- HTTPS only in production
- Input validation on all endpoints
- SQL injection prevention (parameterized queries)
- Rate limiting (100 requests/minute per IP)
- CORS configured for mobile app origins only

## Support

For issues or questions:
1. Check the [design document](../.kiro/specs/bharatverse-mvp/design.md)
2. Review [AGENTS.md](../.kiro/AGENTS.md) for development guidelines
3. Check existing issues in the repository
