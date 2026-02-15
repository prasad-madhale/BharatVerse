# Design Document: BharatVerse MVP

## Overview

BharatVerse MVP is a mobile-first application that delivers daily curated historical articles about Indian history. The system consists of three main components:

1. **Content Pipeline (Python)**: Scrapes historical content from Wikipedia and archive.org, uses LLM (Anthropic Claude) to generate engaging articles with citations
2. **Backend API (Python/FastAPI)**: Provides REST endpoints for article retrieval, search, user authentication, and likes management
3. **Mobile App (Flutter)**: Cross-platform iOS/Android application for browsing and reading articles

The architecture prioritizes simplicity and rapid iteration for MVP validation while maintaining flexibility for future enhancements.

### Design Principles

- **Separation of Concerns**: Content generation, API layer, and mobile UI are independent
- **Async-First**: Python backend uses asyncio for non-blocking operations
- **Stateless API**: REST API is stateless; authentication via JWT tokens
- **Offline-First Mobile**: Flutter app caches articles for offline reading
- **Data-Driven**: All content decisions based on structured data models

## Architecture

```mermaid
graph TB
    subgraph "Content Pipeline (Python)"
        Scheduler[Scheduler/Cron]
        Scraper[Web Scraper]
        LLM[LLM Article Generator]
        Validator[Content Validator]
    end
    
    subgraph "Backend API (FastAPI)"
        API[REST API Endpoints]
        Auth[Authentication Service]
        ArticleService[Article Service]
        SearchService[Search Service]
        LikeService[Like Service]
    end
    
    subgraph "Data Layer"
        DB[(SQLite Database)]
        FileStore[Article JSON Files]
    end
    
    subgraph "Mobile App (Flutter)"
        UI[UI Layer]
        State[State Management]
        Cache[Local Cache]
        HTTP[HTTP Client]
    end
    
    subgraph "External Services"
        Wikipedia[Wikipedia API]
        Archive[Archive.org]
        OAuth[OAuth Providers]
    end
    
    Scheduler -->|Triggers| Scraper
    Scraper -->|Fetches| Wikipedia
    Scraper -->|Fetches| Archive
    Scraper -->|Raw Content| LLM
    LLM -->|Generated Article| Validator
    Validator -->|Valid Article| DB
    Validator -->|Article JSON| FileStore
    
    API -->|Queries| ArticleService
    API -->|Authenticates| Auth
    API -->|Searches| SearchService
    API -->|Manages| LikeService
    
    ArticleService -->|Reads| DB
    ArticleService -->|Reads| FileStore
    SearchService -->|Queries| DB
    Auth -->|Validates| OAuth
    Auth -->|Stores| DB
    LikeService -->|Stores| DB
    
    HTTP -->|Requests| API
    UI -->|Updates| State
    State -->|Persists| Cache
    Cache -->|Reads| HTTP
```

### Database Choice: SQLite vs Supabase

**For MVP, we're using SQLite** for the following reasons:

**SQLite Advantages for MVP**:
1. **Zero Configuration**: No separate database server to set up, manage, or pay for
2. **Simplicity**: Single file database, easy to backup and migrate
3. **Cost**: Completely free, no monthly fees
4. **Performance**: Excellent for read-heavy workloads with low write concurrency (perfect for MVP)
5. **Portability**: Easy to develop locally and deploy anywhere
6. **Low Complexity**: Fewer moving parts means faster MVP development

**SQLite Limitations** (acceptable for MVP):
- Limited concurrent writes (not an issue with daily batch article generation)
- No built-in replication (not needed for MVP scale)
- Single server only (acceptable for MVP traffic)

**Supabase Considerations**:

Supabase is an excellent choice for production, but adds complexity for MVP:

**Supabase Advantages** (more valuable post-MVP):
- Built-in authentication (Google, Facebook OAuth)
- Real-time subscriptions (useful for future social features)
- Row-level security policies
- Auto-generated REST API
- Built-in storage for images/files
- PostgreSQL scalability
- Admin dashboard for content management

**Supabase Trade-offs for MVP**:
- Monthly cost ($25+ for production tier)
- Additional service dependency
- Learning curve for Supabase-specific features
- Overkill for simple CRUD operations
- More complex local development setup

**Migration Path**:

The design allows easy migration to Supabase post-MVP:
1. Replace SQLite with Supabase PostgreSQL
2. Migrate authentication to Supabase Auth
3. Move article JSON files to Supabase Storage
4. Leverage Supabase real-time for future features
5. Use Supabase admin dashboard for content management

**Recommendation**: Start with SQLite for MVP speed and simplicity, migrate to Supabase when:
- User base grows beyond 10,000 active users
- Need real-time features (comments, notifications)
- Want admin dashboard for content management
- Require better scalability and replication

This approach follows the "do things that don't scale" principle for MVPs - optimize for learning and iteration speed, not premature scalability.

### Technology Stack

**Backend (Python)**:
- FastAPI for REST API
- SQLite for structured data (metadata, users, likes)
- Pydantic for data validation
- Anthropic Claude API for LLM
- Playwright for web scraping
- LangChain for Wikipedia integration
- python-dotenv for configuration
- PyJWT for authentication tokens
- passlib for password hashing

**Mobile (Flutter/Dart)**:
- Flutter SDK 3.x
- Provider or Riverpod for state management
- http package for API calls
- shared_preferences for local storage
- sqflite for local database
- cached_network_image for image caching
- flutter_secure_storage for token storage
- google_sign_in for Google OAuth
- flutter_facebook_auth for Facebook OAuth

## Components and Interfaces

### 1. Content Pipeline Components

#### 1.1 Web Scraper

**Purpose**: Fetch historical content from configured sources

**Interface**:
```python
class WebScraper:
    async def scrape_wikipedia(self, topic: str) -> ScrapedContent
    async def scrape_archive_org(self, url: str) -> ScrapedContent
    async def fetch_images(self, urls: list[str]) -> list[ImageData]
```

**Data Models**:
```python
class ScrapedContent:
    source_url: str
    title: str
    raw_text: str
    images: list[ImageData]
    metadata: dict
    scraped_at: datetime

class ImageData:
    url: str
    alt_text: str
    caption: str | None
```

**Behavior**:
- Respects robots.txt and implements rate limiting (1 request per 2 seconds)
- Retries failed requests with exponential backoff (max 3 attempts)
- Extracts text content, images, and metadata
- Preserves source URLs for citations

#### 1.2 LLM Article Generator

**Purpose**: Transform scraped content into engaging historical articles

**Interface**:
```python
class ArticleGenerator:
    def __init__(self, llm_client: AnthropicClient)
    async def generate_article(self, content: ScrapedContent) -> GeneratedArticle
    async def validate_citations(self, article: GeneratedArticle) -> bool
```

**Data Models**:
```python
class GeneratedArticle:
    title: str
    summary: str
    content: str  # Markdown formatted
    sections: list[Section]
    citations: list[Citation]
    reading_time_minutes: int
    generated_at: datetime

class Section:
    heading: str
    content: str
    order: int

class Citation:
    text: str
    source_url: str
    source_name: str
    accessed_date: datetime
```

**Behavior**:
- Uses Claude API with structured prompts for article generation
- Target reading time: 10-15 minutes (1500-2500 words)
- Generates title, summary, structured sections, and citations
- Validates that citations reference actual source URLs
- Implements retry logic for API failures

**LLM Prompt Structure**:
```
You are a historical content curator specializing in Indian history.

Task: Transform the following scraped content into an engaging 10-15 minute read article.

Requirements:
1. Create a compelling title
2. Write a 2-3 sentence summary
3. Structure content into clear sections with headings
4. Target 1500-2500 words
5. Include proper citations with source URLs
6. Use accessible language suitable for general audiences
7. Focus on factual accuracy and historical context

Scraped Content:
{content}

Output Format: JSON matching GeneratedArticle schema
```

#### 1.3 Content Validator

**Purpose**: Ensure generated articles meet quality standards

**Interface**:
```python
class ContentValidator:
    def validate_article(self, article: GeneratedArticle) -> ValidationResult
    def check_word_count(self, content: str) -> bool
    def check_citations(self, citations: list[Citation]) -> bool
    def check_structure(self, sections: list[Section]) -> bool

class ValidationResult:
    is_valid: bool
    errors: list[str]
    warnings: list[str]
    metrics: dict
```

**Validation Rules**:
- Minimum 1500 words
- At least 1 citation
- Must have introduction, body sections, and conclusion
- All citations must have valid URLs
- Reading time between 10-15 minutes

#### 1.4 Scheduler

**Purpose**: Orchestrate daily article generation

**Interface**:
```python
class ArticleScheduler:
    async def generate_daily_article(self) -> Article
    async def select_topic(self) -> str
    async def check_topic_uniqueness(self, topic: str) -> bool
```

**Behavior**:
- Runs daily via cron job or scheduled task
- Selects topics from curated list or trending Indian history topics
- Checks topic uniqueness against existing articles
- Orchestrates scraping → generation → validation → storage pipeline
- Logs all operations for monitoring

### 2. Backend API Components

#### 2.1 Article Service

**Purpose**: Manage article storage and retrieval

**Interface**:
```python
class ArticleService:
    async def save_article(self, article: GeneratedArticle) -> Article
    async def get_daily_article(self) -> Article
    async def get_article_by_id(self, article_id: str) -> Article | None
    async def get_article_by_date(self, date: date) -> Article | None
    async def list_articles(self, limit: int, offset: int) -> list[Article]
    async def search_articles(self, query: str) -> list[Article]
```

**Storage Strategy**:
- Article metadata stored in SQLite (id, title, date, reading_time, etc.)
- Full article content stored as JSON files (for flexibility)
- File naming: `articles/{date}/{article_id}.json`
- Database indexes on: date, title, tags

#### 2.2 Authentication Service

**Purpose**: Handle user registration, login, and session management

**Interface**:
```python
class AuthService:
    async def register_user(self, email: str, password: str) -> User
    async def login_user(self, email: str, password: str) -> AuthToken
    async def verify_oauth(self, provider: str, token: str) -> User
    async def refresh_token(self, refresh_token: str) -> AuthToken
    async def logout_user(self, user_id: str) -> None

class AuthToken:
    access_token: str
    refresh_token: str
    token_type: str
    expires_in: int
```

**Authentication Flow**:
1. **Email/Password Registration**:
   - Validate email format
   - Hash password with bcrypt (cost factor 12)
   - Store user in database
   - Return JWT tokens

2. **Email/Password Login**:
   - Verify credentials
   - Generate JWT access token (expires in 1 hour)
   - Generate JWT refresh token (expires in 30 days)
   - Return tokens

3. **OAuth Flow (Google/Facebook)**:
   - Receive OAuth token from mobile app
   - Verify token with provider
   - Create or retrieve user account
   - Return JWT tokens

**JWT Token Structure**:
```json
{
  "sub": "user_id",
  "email": "user@example.com",
  "exp": 1234567890,
  "iat": 1234567890,
  "type": "access"
}
```

#### 2.3 Search Service

**Purpose**: Enable full-text search across articles

**Interface**:
```python
class SearchService:
    async def search(self, query: str, filters: SearchFilters) -> SearchResults
    async def autocomplete(self, prefix: str, limit: int = 10) -> list[str]
    async def semantic_search(self, query: str, limit: int = 20) -> list[ArticleSearchResult]
    async def index_article(self, article: Article) -> None
    async def generate_embedding(self, text: str) -> list[float]

class SearchFilters:
    date_from: date | None
    date_to: date | None
    tags: list[str] | None

class SearchResults:
    results: list[ArticleSearchResult]
    total_count: int
    query: str

class ArticleSearchResult:
    article: Article
    relevance_score: float
    matched_snippets: list[str]
```

**Search Methods**:

1. **Full-Text Search** (`search`):
   - Uses SQLite FTS5 for primary search
   - Returns articles ranked by BM25 relevance
   - Highlights matching terms in snippets

2. **Autocomplete** (`autocomplete`):
   - Queries `search_suggestions` table with prefix matching
   - Returns top suggestions ordered by frequency
   - Example: `autocomplete("maur")` → `["Mauryan Empire", "Mauryan Dynasty", "Mauryan Architecture"]`

3. **Semantic Search** (`semantic_search`):
   - Generates embedding for query using LLM
   - Computes cosine similarity with article embeddings
   - Returns semantically similar articles
   - Example: Query "ancient rulers" finds articles about "emperors", "kings", "dynasties"

**Indexing Process**:
When a new article is added:
1. Add to FTS5 index (automatic via trigger)
2. Extract search terms (title words, tags, entities) → add to `search_suggestions`
3. Generate embedding (optional) → store in `article_embeddings`

**Search Implementation**:

The search system uses a hybrid approach combining three techniques:

1. **Full-Text Search (SQLite FTS5)**:
   - Primary search mechanism using BM25 ranking algorithm
   - Search fields: title, content, tags
   - Supports prefix matching for partial word queries
   - Fast and efficient for exact and near-exact matches

2. **Autocomplete Suggestions**:
   - Pre-computed search suggestions stored in `search_suggestions` table
   - Populated from article titles, tags, person names, event names, and historical periods
   - Prefix-based matching for instant suggestions as user types
   - Updated automatically when new articles are added
   - Example: User types "maur" → suggests ["Mauryan Empire", "Mauryan Dynasty", "Mauryan Architecture"]

3. **Semantic Similarity Search (Optional)**:
   - Article embeddings generated using Claude/OpenAI embedding models
   - Stored as JSON arrays in SQLite (embeddings table)
   - Enables semantic search: "emperor" finds articles about "kings", "rulers", "monarchs"
   - Computed on-demand: query embedding → cosine similarity with article embeddings
   - Fallback to FTS5 if embeddings not available

**Search Flow**:
```
User Query → Autocomplete Suggestions (instant)
          ↓
User Submits → FTS5 Search (primary results)
          ↓
          → Semantic Search (enhanced results, optional)
          ↓
          → Merge & Rank Results → Return to User
```

**Performance**:
- Autocomplete: < 50ms (indexed prefix search)
- FTS5 Search: < 200ms (full-text search)
- Semantic Search: < 500ms (embedding similarity computation)

**Highlight matching terms in results**

#### 2.4 Like Service

**Purpose**: Track user article likes for future personalization

**Interface**:
```python
class LikeService:
    async def like_article(self, user_id: str, article_id: str) -> None
    async def unlike_article(self, user_id: str, article_id: str) -> None
    async def is_liked(self, user_id: str, article_id: str) -> bool
    async def get_user_likes(self, user_id: str) -> list[Article]
    async def get_article_like_count(self, article_id: str) -> int
```

**Data Model**:
```python
class Like:
    id: str
    user_id: str
    article_id: str
    created_at: datetime
```

**Storage**:
- Stored in SQLite with composite unique index on (user_id, article_id)
- Enables efficient queries for user likes and article like counts

#### 2.5 REST API Endpoints

**Article Endpoints**:
```
GET  /api/v1/articles/daily              - Get today's daily article
GET  /api/v1/articles/{id}               - Get article by ID
GET  /api/v1/articles                    - List articles (paginated)
GET  /api/v1/articles/search?q=...       - Search articles (FTS5)
GET  /api/v1/articles/search/autocomplete?q=... - Get autocomplete suggestions
GET  /api/v1/articles/search/semantic?q=... - Semantic similarity search (optional)
```

**Authentication Endpoints**:
```
POST /api/v1/auth/register           - Register with email/password
POST /api/v1/auth/login              - Login with email/password
POST /api/v1/auth/oauth/google       - OAuth login with Google
POST /api/v1/auth/oauth/facebook     - OAuth login with Facebook
POST /api/v1/auth/refresh            - Refresh access token
POST /api/v1/auth/logout             - Logout user
```

**Like Endpoints** (Authenticated):
```
POST   /api/v1/articles/{id}/like    - Like an article
DELETE /api/v1/articles/{id}/like    - Unlike an article
GET    /api/v1/users/me/likes        - Get user's liked articles
```

**Request/Response Examples**:

```json
// GET /api/v1/articles/daily
{
  "id": "art_20250228_001",
  "title": "The Mauryan Empire: India's First Great Dynasty",
  "summary": "Explore the rise and fall of the Mauryan Empire...",
  "date": "2025-02-28",
  "reading_time_minutes": 12,
  "author": "BharatVerse AI",
  "tags": ["ancient-india", "mauryan-empire", "chandragupta"],
  "content_url": "/api/v1/articles/art_20250228_001/content",
  "image_url": "https://example.com/images/mauryan.jpg",
  "is_liked": false
}

// POST /api/v1/auth/register
Request:
{
  "email": "user@example.com",
  "password": "SecurePass123!"
}

Response:
{
  "user": {
    "id": "usr_123",
    "email": "user@example.com",
    "created_at": "2025-02-28T10:00:00Z"
  },
  "tokens": {
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "token_type": "Bearer",
    "expires_in": 3600
  }
}
```

### 3. Mobile App Components

#### 3.1 State Management

**Architecture**: Provider pattern with ChangeNotifier

**State Classes**:
```dart
class ArticleState extends ChangeNotifier {
  Article? dailyArticle;
  List<Article> articles = [];
  bool isLoading = false;
  String? error;
  
  Future<void> fetchDailyArticle();
  Future<void> fetchArticles({int page = 0});
  Future<void> searchArticles(String query);
}

class AuthState extends ChangeNotifier {
  User? currentUser;
  bool isAuthenticated = false;
  String? authToken;
  
  Future<void> register(String email, String password);
  Future<void> login(String email, String password);
  Future<void> loginWithGoogle();
  Future<void> loginWithFacebook();
  Future<void> logout();
}

class LikeState extends ChangeNotifier {
  Set<String> likedArticleIds = {};
  
  Future<void> toggleLike(String articleId);
  Future<void> fetchUserLikes();
  bool isLiked(String articleId);
}
```

#### 3.2 UI Components

**Screen Structure**:
```
HomeScreen
├── DailyArticleCard (featured)
├── ArticleListView (past articles)
└── BottomNavigationBar

ArticleDetailScreen
├── ArticleHeader (title, date, reading time)
├── ArticleContent (markdown rendered)
├── CitationsSection
└── LikeButton

SearchScreen
├── SearchBar
├── SearchFilters
└── SearchResultsList

AuthScreen
├── EmailLoginForm
├── OAuthButtons (Google, Facebook)
└── RegisterLink

ProfileScreen (future)
└── LikedArticlesList
```

**Key Widgets**:
```dart
class DailyArticleCard extends StatelessWidget {
  final Article article;
  // Displays featured daily article with image, title, summary
}

class ArticleListTile extends StatelessWidget {
  final Article article;
  // Compact article display for lists
}

class ArticleContentView extends StatelessWidget {
  final String markdownContent;
  // Renders markdown with proper typography
}

class LikeButton extends StatefulWidget {
  final String articleId;
  final bool isLiked;
  final VoidCallback onToggle;
  // Animated like button with heart icon
}
```

#### 3.3 Data Layer

**API Client**:
```dart
class ApiClient {
  final String baseUrl;
  final http.Client httpClient;
  
  Future<Article> getDailyArticle();
  Future<Article> getArticle(String id);
  Future<List<Article>> listArticles({int page = 0, int limit = 20});
  Future<List<Article>> searchArticles(String query);
  Future<List<String>> getAutocompleteSuggestions(String prefix);
  Future<List<Article>> semanticSearch(String query);
  
  Future<AuthResponse> register(String email, String password);
  Future<AuthResponse> login(String email, String password);
  Future<AuthResponse> oauthLogin(String provider, String token);
  
  Future<void> likeArticle(String articleId);
  Future<void> unlikeArticle(String articleId);
  Future<List<Article>> getUserLikes();
}
```

**Local Cache**:
```dart
class ArticleCache {
  final Database db;
  
  Future<void> cacheArticle(Article article);
  Future<Article?> getCachedArticle(String id);
  Future<List<Article>> getCachedArticles();
  Future<void> clearOldCache({int daysToKeep = 7});
}

class SecureStorage {
  Future<void> saveAuthToken(String token);
  Future<String?> getAuthToken();
  Future<void> deleteAuthToken();
}
```

## Data Models

### Core Data Models

**Article** (Shared across backend and mobile):
```python
class Article(BaseModel):
    id: str  # Format: art_YYYYMMDD_NNN
    title: str
    summary: str  # 2-3 sentences
    content: str  # Markdown formatted
    sections: list[Section]
    citations: list[Citation]
    date: date  # Publication date
    reading_time_minutes: int
    author: str  # "BharatVerse AI"
    tags: list[str]  # e.g., ["ancient-india", "mauryan-empire"]
    image_url: str | None
    created_at: datetime
    updated_at: datetime
```

**User**:
```python
class User(BaseModel):
    id: str  # Format: usr_XXXXX
    email: str
    password_hash: str | None  # None for OAuth-only users
    oauth_provider: str | None  # "google", "facebook", or None
    oauth_id: str | None
    created_at: datetime
    last_login: datetime
```

**Like**:
```python
class Like(BaseModel):
    id: str
    user_id: str
    article_id: str
    created_at: datetime
```

### Database Schema

**SQLite Tables**:

```sql
-- Articles metadata
CREATE TABLE articles (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    date DATE NOT NULL,
    reading_time_minutes INTEGER NOT NULL,
    author TEXT NOT NULL,
    tags TEXT NOT NULL,  -- JSON array
    image_url TEXT,
    content_file_path TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_articles_date ON articles(date DESC);
CREATE INDEX idx_articles_tags ON articles(tags);

-- Full-text search index
CREATE VIRTUAL TABLE articles_fts USING fts5(
    article_id UNINDEXED,
    title,
    content,
    tags,
    content=articles
);

-- Users
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT,
    oauth_provider TEXT,
    oauth_id TEXT,
    created_at TIMESTAMP NOT NULL,
    last_login TIMESTAMP NOT NULL
);

CREATE INDEX idx_users_email ON users(email);
CREATE UNIQUE INDEX idx_users_oauth ON users(oauth_provider, oauth_id) 
    WHERE oauth_provider IS NOT NULL;

-- Likes
CREATE TABLE likes (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    article_id TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX idx_likes_user_article ON likes(user_id, article_id);
CREATE INDEX idx_likes_user ON likes(user_id);
CREATE INDEX idx_likes_article ON likes(article_id);

-- Search suggestions for autocomplete
CREATE TABLE search_suggestions (
    id TEXT PRIMARY KEY,
    term TEXT NOT NULL,
    category TEXT NOT NULL,  -- 'title', 'tag', 'person', 'event', 'period'
    frequency INTEGER DEFAULT 1,  -- How often this term appears
    article_count INTEGER DEFAULT 0,  -- Number of articles with this term
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_search_suggestions_term ON search_suggestions(term);
CREATE INDEX idx_search_suggestions_category ON search_suggestions(category);
CREATE INDEX idx_search_suggestions_frequency ON search_suggestions(frequency DESC);

-- Article embeddings for semantic search (optional)
CREATE TABLE article_embeddings (
    article_id TEXT PRIMARY KEY,
    embedding TEXT NOT NULL,  -- JSON array of floats (e.g., 1536 dimensions for OpenAI)
    model TEXT NOT NULL,  -- 'claude-3-embedding' or 'text-embedding-ada-002'
    created_at TIMESTAMP NOT NULL,
    FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE
);

CREATE INDEX idx_embeddings_article ON article_embeddings(article_id);
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*


### Content Pipeline Properties

**Property 1: Scraping completeness**
*For any* scraping job on a valid source URL, the scraped content should contain text content, source URL, and metadata (images may be optional depending on source).
**Validates: Requirements 1.1, 1.2, 1.3**

**Property 2: Scraping resilience**
*For any* list of source URLs where some are unavailable, the scraper should successfully process available sources and log errors for unavailable ones without failing the entire job.
**Validates: Requirements 1.4**

**Property 3: Article generation completeness**
*For any* valid scraped content, the generated article should contain a title, summary, structured sections, at least one citation with source URL, and reading time between 10-15 minutes.
**Validates: Requirements 2.1, 2.2, 2.3, 2.4**

**Property 4: Retry with exponential backoff**
*For any* failed article generation attempt, the system should retry with exponentially increasing delays (e.g., 1s, 2s, 4s) up to a maximum number of attempts.
**Validates: Requirements 2.6**

### Storage and Retrieval Properties

**Property 5: Article persistence round-trip**
*For any* valid generated article, storing it and then retrieving it by ID should return an equivalent article with all fields preserved.
**Validates: Requirements 3.1, 3.3**

**Property 6: Query method completeness**
*For any* stored article, it should be retrievable by its ID, by its publication date, and should appear in paginated list queries.
**Validates: Requirements 3.2**

**Property 7: Date-based ordering**
*For any* set of articles with different publication dates, querying all articles should return them ordered by publication date (newest first).
**Validates: Requirements 3.4**

**Property 8: Storage validation**
*For any* article missing required fields (title, content, date, etc.), attempting to store it should fail with a validation error.
**Validates: Requirements 3.5**

### Daily Article Properties

**Property 9: One daily article per day**
*For any* calendar date, there should be exactly one article designated as the daily article for that date.
**Validates: Requirements 4.1**

**Property 10: Daily article updates with date**
*For any* two consecutive calendar dates, the daily article for date N should be different from the daily article for date N+1.
**Validates: Requirements 4.3**

**Property 11: Topic uniqueness**
*For any* new article topic, if an article with the same topic already exists in the database, the new article should not be published unless it's marked as containing substantially new information.
**Validates: Requirements 4.4**

### Search Properties

**Property 12: Search result relevance**
*For any* search query and article, if the article's title or content contains the query terms, it should appear in the search results.
**Validates: Requirements 7.2**

**Property 13: Search result ordering**
*For any* search query with multiple matching articles, results should be ordered by relevance score in descending order.
**Validates: Requirements 7.3**

**Property 14: Multi-field search**
*For any* search query, the system should find matches in article titles, content, tags, and metadata fields (person names, event names, periods).
**Validates: Requirements 7.6**

### Offline Cache Properties

**Property 15: View-triggered caching**
*For any* article viewed by a user, the article should be stored in the local cache immediately after viewing.
**Validates: Requirements 8.1**

**Property 16: Offline article access**
*For any* cached article, when the device is offline, the article should be retrievable from the cache with all content intact.
**Validates: Requirements 8.2**

**Property 17: Minimum cache retention**
*For any* point in time, the cache should contain at least the last 7 days of viewed articles (or all articles if fewer than 7 days exist).
**Validates: Requirements 8.3**

**Property 18: LRU cache eviction**
*For any* cache at capacity, when a new article is cached, the oldest article by view date should be evicted first.
**Validates: Requirements 8.4**

**Property 19: Cache synchronization**
*For any* cached article, when online and the article has been updated on the server, fetching the article should update the cached version.
**Validates: Requirements 8.5**

### API Properties

**Property 20: Pagination consistency**
*For any* paginated article list request, the union of all pages should equal the complete article set, with no duplicates or missing articles.
**Validates: Requirements 9.3**

**Property 21: API response format**
*For any* successful API request, the response should be valid JSON with appropriate HTTP status code (200, 201, etc.), and for any failed request, the response should include an error message with appropriate error status code (400, 404, 500, etc.).
**Validates: Requirements 9.5, 9.6**

### Validation Properties

**Property 22: Article quality validation**
*For any* generated article, it should pass validation if and only if it contains at least 1500 words, at least one citation, and properly formatted sections (introduction, body, conclusion).
**Validates: Requirements 10.1, 10.2, 10.3**

**Property 23: Validation rejection**
*For any* article that fails quality validation, attempting to store it should be rejected and validation errors should be logged.
**Validates: Requirements 10.4**

**Property 24: Metrics tracking**
*For any* generated article, the system should record quality metrics including word count, citation count, and generation time.
**Validates: Requirements 10.5**

### Logging Properties

**Property 25: Error logging completeness**
*For any* error occurring in the content pipeline or API, a log entry should be created containing timestamp, error context, and stack trace.
**Validates: Requirements 11.1, 11.3**

**Property 26: Log level structure**
*For any* log entry, it should have a severity level (DEBUG, INFO, WARNING, ERROR) and follow a consistent structured format.
**Validates: Requirements 11.4**

### Authentication Properties

**Property 27: Email validation**
*For any* registration attempt with email and password, the system should reject invalid email formats and weak passwords (less than 8 characters, no special characters).
**Validates: Requirements 12.4**

**Property 28: Session creation**
*For any* successful login (email/password or OAuth), the system should create an authenticated session with a valid JWT token.
**Validates: Requirements 12.5**

**Property 29: Password security**
*For any* user registered with email/password, the stored password should be hashed (not plaintext) using bcrypt or equivalent.
**Validates: Requirements 12.6**

**Property 30: Logout session termination**
*For any* authenticated user who logs out, subsequent API requests with their previous token should be rejected as unauthorized.
**Validates: Requirements 12.7**

### Like Properties

**Property 31: Like toggle behavior**
*For any* article and authenticated user, liking an unliked article should create a like record, and liking an already-liked article should remove the like record (toggle).
**Validates: Requirements 13.2, 13.3**

**Property 32: Like persistence**
*For any* article liked by a user, the like should persist across app restarts and be retrievable via the user's liked articles API.
**Validates: Requirements 13.5, 13.6**

### Search Properties (Enhanced)

**Property 33: Autocomplete prefix matching**
*For any* search prefix entered by a user, the autocomplete system should return suggestions that start with that prefix, ordered by frequency/relevance.
**Validates: Requirements 7.1**

**Property 34: Autocomplete performance**
*For any* autocomplete query, the system should return suggestions within 50ms.
**Validates: Requirements 7.1**

**Property 35: Semantic search similarity**
*For any* semantic search query, articles returned should be semantically related to the query even if they don't contain exact keyword matches.
**Validates: Requirements 7.2, 7.6**

**Property 36: Search suggestion updates**
*For any* newly added article, search suggestions should be automatically extracted and added to the suggestions table.
**Validates: Requirements 7.1**

## Search Implementation Details

### Autocomplete Implementation

**Suggestion Extraction Process**:
When a new article is indexed, the system extracts searchable terms:

```python
async def extract_search_suggestions(article: Article) -> list[SearchSuggestion]:
    suggestions = []
    
    # Extract from title (split into meaningful phrases)
    title_terms = extract_phrases(article.title)
    for term in title_terms:
        suggestions.append(SearchSuggestion(
            term=term,
            category='title',
            frequency=1
        ))
    
    # Extract from tags
    for tag in article.tags:
        suggestions.append(SearchSuggestion(
            term=tag.replace('-', ' ').title(),
            category='tag',
            frequency=1
        ))
    
    # Extract named entities (persons, events, periods) using NER
    entities = extract_entities(article.content)
    for entity in entities:
        suggestions.append(SearchSuggestion(
            term=entity.text,
            category=entity.type,  # 'person', 'event', 'period'
            frequency=1
        ))
    
    return suggestions
```

**Autocomplete Query**:
```python
async def autocomplete(prefix: str, limit: int = 10) -> list[str]:
    query = """
        SELECT DISTINCT term 
        FROM search_suggestions 
        WHERE term LIKE ? || '%'
        ORDER BY frequency DESC, article_count DESC
        LIMIT ?
    """
    results = await db.execute(query, (prefix.lower(), limit))
    return [row['term'] for row in results]
```

**Example Autocomplete Flow**:
```
User types: "maur"
↓
Query: SELECT term FROM search_suggestions WHERE term LIKE 'maur%'
↓
Results: ["Mauryan Empire", "Mauryan Dynasty", "Mauryan Architecture", "Mauryan Art"]
↓
Display suggestions to user in real-time
```

### Semantic Search Implementation

**Embedding Generation**:
```python
async def generate_embedding(text: str) -> list[float]:
    """Generate embedding using Claude or OpenAI API"""
    # Option 1: Use Claude (if available)
    response = await anthropic_client.embeddings.create(
        model="claude-3-embedding",
        input=text
    )
    return response.embedding
    
    # Option 2: Use OpenAI (fallback)
    response = await openai_client.embeddings.create(
        model="text-embedding-ada-002",
        input=text
    )
    return response.data[0].embedding
```

**Cosine Similarity Computation**:
```python
def cosine_similarity(vec1: list[float], vec2: list[float]) -> float:
    """Compute cosine similarity between two vectors"""
    import numpy as np
    v1 = np.array(vec1)
    v2 = np.array(vec2)
    return np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2))

async def semantic_search(query: str, limit: int = 20) -> list[ArticleSearchResult]:
    # Generate query embedding
    query_embedding = await generate_embedding(query)
    
    # Fetch all article embeddings (or use approximate nearest neighbor for scale)
    embeddings = await db.execute(
        "SELECT article_id, embedding FROM article_embeddings"
    )
    
    # Compute similarities
    results = []
    for row in embeddings:
        article_embedding = json.loads(row['embedding'])
        similarity = cosine_similarity(query_embedding, article_embedding)
        results.append((row['article_id'], similarity))
    
    # Sort by similarity and return top results
    results.sort(key=lambda x: x[1], reverse=True)
    top_article_ids = [article_id for article_id, _ in results[:limit]]
    
    # Fetch full article data
    articles = await fetch_articles_by_ids(top_article_ids)
    return articles
```

**Hybrid Search Strategy**:
```python
async def hybrid_search(query: str) -> SearchResults:
    """Combine FTS5 and semantic search for best results"""
    
    # 1. FTS5 search (fast, exact matches)
    fts_results = await fts5_search(query, limit=15)
    
    # 2. Semantic search (slower, semantic matches)
    semantic_results = await semantic_search(query, limit=10)
    
    # 3. Merge and deduplicate
    seen_ids = set()
    merged_results = []
    
    # Prioritize FTS5 results (exact matches)
    for result in fts_results:
        if result.article.id not in seen_ids:
            merged_results.append(result)
            seen_ids.add(result.article.id)
    
    # Add semantic results (semantic matches)
    for result in semantic_results:
        if result.article.id not in seen_ids:
            merged_results.append(result)
            seen_ids.add(result.article.id)
    
    return SearchResults(
        results=merged_results[:20],
        total_count=len(merged_results),
        query=query
    )
```

**Example Semantic Search**:
```
User query: "ancient rulers of India"
↓
Generate embedding for query
↓
Compare with article embeddings using cosine similarity
↓
Results include articles about:
- "Mauryan Empire" (contains "Chandragupta Maurya")
- "Gupta Dynasty" (contains "Samudragupta")
- "Mughal Emperors" (contains "Akbar", "Shah Jahan")
- "Chola Kings" (contains "Raja Raja Chola")
↓
Even though articles don't contain exact phrase "ancient rulers"
```

### Search Performance Optimization

**Caching Strategy**:
- Cache popular search queries and their results (TTL: 1 hour)
- Cache autocomplete suggestions for common prefixes
- Pre-compute embeddings during article indexing (not on-demand)

**Indexing Strategy**:
- Update search suggestions asynchronously after article creation
- Generate embeddings in background job (not blocking article creation)
- Batch update FTS5 index for multiple articles

**Scaling Considerations**:
- For MVP: In-memory cosine similarity (acceptable for < 1000 articles)
- Post-MVP: Use approximate nearest neighbor (ANN) libraries like FAISS or Annoy
- Future: Migrate to dedicated search engine (Meilisearch, Elasticsearch)

## Error Handling

### Content Pipeline Errors

**Scraping Errors**:
- Network timeouts: Retry with exponential backoff (max 3 attempts)
- Invalid HTML/content: Log error, skip source, continue with other sources
- Rate limit exceeded: Wait and retry after delay period
- robots.txt violation: Skip source, log warning

**LLM Generation Errors**:
- API timeout: Retry with exponential backoff (max 3 attempts)
- Invalid response format: Log error, retry with modified prompt
- Rate limit exceeded: Queue for later processing
- Content policy violation: Log error, mark topic as problematic

**Validation Errors**:
- Word count too low: Reject article, log metrics, retry generation with "expand content" instruction
- Missing citations: Reject article, retry generation with "include citations" instruction
- Malformed structure: Reject article, retry generation with structure template

### API Errors

**Client Errors (4xx)**:
- 400 Bad Request: Invalid request format or parameters
- 401 Unauthorized: Missing or invalid authentication token
- 403 Forbidden: Valid token but insufficient permissions
- 404 Not Found: Requested resource doesn't exist
- 429 Too Many Requests: Rate limit exceeded

**Server Errors (5xx)**:
- 500 Internal Server Error: Unexpected server error
- 503 Service Unavailable: Server overloaded or maintenance

**Error Response Format**:
```json
{
  "error": {
    "code": "ARTICLE_NOT_FOUND",
    "message": "Article with ID 'art_20250228_001' not found",
    "details": {
      "article_id": "art_20250228_001"
    }
  }
}
```

### Mobile App Errors

**Network Errors**:
- No internet connection: Display cached content, show offline indicator
- Request timeout: Retry with exponential backoff, show loading indicator
- Server error: Display user-friendly error message, offer retry

**Authentication Errors**:
- Invalid credentials: Display error message, allow retry
- Expired token: Automatically refresh token, retry request
- OAuth failure: Display provider-specific error, offer alternative login methods

**Cache Errors**:
- Cache full: Evict oldest articles, log warning
- Corrupted cache: Clear cache, re-fetch articles
- Database error: Fallback to in-memory cache, log error

## Testing Strategy

### Dual Testing Approach

The BharatVerse MVP will employ both unit testing and property-based testing to ensure comprehensive coverage:

**Unit Tests**: Focus on specific examples, edge cases, and integration points
- Test specific scraping scenarios (Wikipedia page, archive.org page)
- Test authentication flows (email/password, Google OAuth, Facebook OAuth)
- Test API endpoints with known inputs and expected outputs
- Test UI components with specific article data
- Test error handling with simulated failures

**Property-Based Tests**: Verify universal properties across all inputs
- Test scraping with randomly generated URLs and content
- Test article generation with random scraped content
- Test storage and retrieval with random article data
- Test search with random queries and article sets
- Test cache behavior with random article sequences
- Test authentication with random credentials
- Test like toggle with random user/article combinations

### Property-Based Testing Configuration

**Framework**: 
- Python backend: `hypothesis` library
- Flutter mobile: `test` package with custom property test helpers

**Configuration**:
- Minimum 100 iterations per property test
- Each test tagged with feature name and property number
- Tag format: `# Feature: bharatverse-mvp, Property {N}: {property_text}`

**Example Property Test (Python)**:
```python
from hypothesis import given, strategies as st
import pytest

@given(
    article=st.builds(
        Article,
        title=st.text(min_size=10, max_size=200),
        content=st.text(min_size=1500, max_size=5000),
        citations=st.lists(st.builds(Citation), min_size=1)
    )
)
@pytest.mark.property_test
def test_article_persistence_round_trip(article):
    """
    Feature: bharatverse-mvp, Property 5: Article persistence round-trip
    For any valid generated article, storing it and then retrieving it by ID
    should return an equivalent article with all fields preserved.
    """
    # Store article
    stored_id = article_service.save_article(article)
    
    # Retrieve article
    retrieved = article_service.get_article_by_id(stored_id)
    
    # Assert equivalence
    assert retrieved is not None
    assert retrieved.title == article.title
    assert retrieved.content == article.content
    assert len(retrieved.citations) == len(article.citations)
```

**Example Property Test (Dart/Flutter)**:
```dart
import 'package:test/test.dart';

void main() {
  group('Property Tests', () {
    test('Like toggle behavior', () async {
      // Feature: bharatverse-mvp, Property 31: Like toggle behavior
      // For any article and authenticated user, liking an unliked article
      // should create a like record, and liking an already-liked article
      // should remove the like record (toggle).
      
      for (int i = 0; i < 100; i++) {
        final userId = generateRandomUserId();
        final articleId = generateRandomArticleId();
        
        // Initially not liked
        expect(await likeService.isLiked(userId, articleId), false);
        
        // Like article
        await likeService.likeArticle(userId, articleId);
        expect(await likeService.isLiked(userId, articleId), true);
        
        // Unlike article (toggle)
        await likeService.likeArticle(userId, articleId);
        expect(await likeService.isLiked(userId, articleId), false);
      }
    });
  });
}
```

### Test Coverage Goals

- **Backend**: 80% code coverage minimum
- **Mobile**: 70% code coverage minimum (UI testing is harder)
- **Property Tests**: All 32 correctness properties implemented
- **Integration Tests**: End-to-end flows (scraping → storage → API → mobile)

### Testing Pyramid

```
        /\
       /  \
      / E2E \          10% - End-to-end tests
     /______\
    /        \
   /Integration\       20% - Integration tests
  /____________\
 /              \
/  Unit + Props  \     70% - Unit and property tests
/__________________\
```

## Deployment Architecture

### MVP Deployment (Simplified)

For MVP, we'll use a simple deployment architecture:

**Backend**:
- Single Python server (FastAPI) running on a VPS or cloud instance
- SQLite database (file-based, no separate DB server needed)
- Article JSON files stored on local filesystem
- Scheduled cron job for daily article generation

**Mobile**:
- Flutter apps published to Google Play Store and Apple App Store
- Apps connect directly to backend API via HTTPS

**Infrastructure**:
- Domain with SSL certificate (Let's Encrypt)
- Nginx as reverse proxy
- Basic monitoring and logging

### Future Scalability Considerations

While MVP uses simple architecture, the design allows for future scaling:

- **Database**: SQLite → PostgreSQL for better concurrency
- **File Storage**: Local filesystem → S3/Cloud Storage for scalability
- **API**: Single server → Load-balanced multiple instances
- **Cache**: In-app cache → Redis for shared caching
- **Search**: SQLite FTS → Elasticsearch for advanced search
- **Queue**: Direct execution → Celery/RabbitMQ for async tasks

## Security Considerations

### Authentication Security

- Passwords hashed with bcrypt (cost factor 12)
- JWT tokens with short expiration (1 hour access, 30 days refresh)
- Secure token storage on mobile (flutter_secure_storage)
- OAuth tokens validated with provider APIs
- HTTPS only for all API communication

### Data Security

- User data encrypted at rest (database encryption)
- API rate limiting to prevent abuse
- Input validation on all endpoints
- SQL injection prevention (parameterized queries)
- XSS prevention (content sanitization)

### Privacy

- Minimal data collection (email, likes only)
- No tracking or analytics in MVP
- User data deletion on account deletion
- Compliance with basic privacy standards

## Performance Considerations

### Backend Performance

- Article generation: Max 5 minutes per article (acceptable for daily batch)
- API response time: Target < 500ms for article retrieval
- Database queries: Indexed for common queries (date, ID, search)
- Rate limiting: 100 requests per minute per IP

### Mobile Performance

- App launch time: Target < 2 seconds
- Article load time: Target < 1 second (cached) or < 3 seconds (network)
- Smooth scrolling: 60 FPS target
- Image loading: Progressive loading with placeholders
- Cache size: Max 100MB (configurable)

### Optimization Strategies

- Lazy loading for article lists
- Image compression and caching
- Pagination for large result sets
- Database query optimization
- Async operations for non-blocking UI

## Monitoring and Observability

### Logging

- Structured JSON logs
- Log levels: DEBUG, INFO, WARNING, ERROR, CRITICAL
- Log rotation (daily, max 30 days retention)
- Centralized logging (future: ELK stack or similar)

### Metrics

- Article generation success rate
- API response times
- Error rates by endpoint
- User registration and login rates
- Article view counts
- Like counts per article

### Alerts

- Critical errors in content pipeline
- API downtime or high error rates
- Database connection failures
- Disk space warnings

## Future Enhancements (Post-MVP)

While out of scope for MVP, the design accommodates these future features:

1. **Multilingual Support**: Add translation service, language detection
2. **Push Notifications**: Integrate FCM/APNS for daily article notifications
3. **Recommendations**: Use like data for personalized article suggestions
4. **Social Features**: Add comments, sharing, user profiles
5. **Subscription System**: Integrate payment gateway, premium content
6. **Content Management**: Admin UI for manual curation and editing
7. **Analytics Dashboard**: User engagement metrics, content performance
8. **Advanced Search**: Filters, facets, autocomplete
9. **Reading History**: Track and display user reading progress
10. **Bookmarks**: Save articles for later reading
