# Implementation Plan: BharatVerse MVP

## Overview

This implementation plan covers the complete BharatVerse MVP system: backend API (FastAPI), content pipeline (scraping + LLM generation), database (Supabase PostgreSQL with full-text search), authentication (Supabase Auth with OAuth), mobile app (Flutter), and comprehensive testing. The plan includes cleanup of existing code and implementation of all 36 correctness properties through property-based testing.

## Tasks

- [x] 1. Clean up existing code and project structure
  - [x] 1.1 Remove or refactor scrapper/agent_main.py
    - Remove Google Gemini dependencies
    - Clean up unused imports and code
    - _Requirements: Project setup_
  
  - [x] 1.2 Update scrapper/model/article.py to match design schema
    - Update Article model with all fields from design (id, title, summary, content, sections, citations, date, reading_time_minutes, author, tags, image_url, created_at, updated_at)
    - Add Section and Citation models
    - Add Pydantic validation
    - _Requirements: 3.1, 3.5_
  
  - [x] 1.3 Replace scrapper/scrapper_main.py with proper pipeline structure
    - Remove Wikipedia test code
    - Set up proper async pipeline structure
    - Add configuration loading from .env
    - _Requirements: 1.1, 2.1_

- [x] 2. Set up backend project structure and dependencies
  - [x] 2.1 Create backend directory structure
    - Create backend/ directory with subdirectories: api/, services/, models/, database/, utils/
    - Set up __init__.py files
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  
  - [x] 2.2 Create requirements.txt for backend dependencies
    - Add FastAPI, uvicorn, supabase-py, pydantic, anthropic, crawl4ai, python-dotenv, asyncpg, httpx, pytest, hypothesis
    - _Requirements: All backend requirements_
  
  - [x] 2.3 Set up configuration management
    - Create config.py for loading environment variables
    - Add settings for Supabase URL, Supabase API key, Anthropic API key, OAuth credentials
    - _Requirements: 2.1, 12.2, 12.3_

- [x] 3. Implement database schema and Supabase setup
  - [x] 3.1 Set up Supabase project and configure environment
    - Create Supabase project in dashboard
    - Get Supabase URL and API keys
    - Configure environment variables in .env
    - _Requirements: 3.1_
  
  - [x] 3.2 Create PostgreSQL database schema
    - Create articles table with JSONB content and tsvector for full-text search
    - Create user_profiles table (extends Supabase auth.users)
    - Create likes table with Row-Level Security policies
    - Create search_suggestions table for autocomplete
    - Create article_embeddings table with pgvector extension
    - Add indexes and triggers for automatic tsvector updates
    - _Requirements: 3.1, 3.2, 7.1, 7.2, 12.1, 13.1_
  
  - [x] 3.3 Configure Supabase Storage buckets
    - Create article-images bucket for storing article images
    - Set up storage policies (public read, authenticated write)
    - _Requirements: 3.1_
  
  - [ ] 3.4 Configure Supabase Auth providers
    - Enable Google OAuth in Supabase dashboard
    - Enable Facebook OAuth in Supabase dashboard
    - Configure OAuth redirect URLs
    - _Requirements: 12.2, 12.3_
  
  - [x] 3.5 Create Supabase client connection module
    - Implement async Supabase client initialization
    - Add connection pooling configuration
    - Add error handling for connection failures
    - _Requirements: 3.1_
  
  - [x]* 3.6 Write property test for database schema
    - **Property 5: Article persistence round-trip**
    - **Validates: Requirements 3.1, 3.3**
  
  - [ ]* 3.7 Write property test for query methods
    - **Property 6: Query method completeness**
    - **Validates: Requirements 3.2**

- [ ] 4. Implement content pipeline - Web scraper
  - [x] 4.1 Create WebScraper class with Crawl4AI integration
    - Implement scrape_url method using Crawl4AI's AsyncWebCrawler
    - Implement scrape_wikipedia method (wrapper for Wikipedia URLs)
    - Implement scrape_archive_org method (wrapper for archive.org URLs)
    - Extract markdown content, images, and metadata
    - Preserve source URLs for citations
    - _Requirements: 1.1, 1.2, 1.3_
  
  - [ ] 4.2 Add Crawl4AI configuration and optimization
    - Configure AsyncWebCrawler with appropriate settings
    - Implement content extraction strategies
    - Handle different content formats (articles, archives)
    - _Requirements: 1.1, 1.2_
  
  - [ ] 4.3 Implement rate limiting and robots.txt respect
    - Add rate limiter (1 request per 2 seconds)
    - Check robots.txt before scraping
    - _Requirements: 1.5_
  
  - [ ] 4.4 Add error handling and retry logic
    - Implement exponential backoff for failed requests
    - Log errors without failing entire job
    - _Requirements: 1.4_
  
  - [ ]* 4.5 Write property test for scraping completeness
    - **Property 1: Scraping completeness**
    - **Validates: Requirements 1.1, 1.2, 1.3**
  
  - [ ]* 4.6 Write property test for scraping resilience
    - **Property 2: Scraping resilience**
    - **Validates: Requirements 1.4**

- [ ] 5. Implement content pipeline - LLM article generator
  - [ ] 5.1 Create ArticleGenerator class with Anthropic Claude integration
    - Initialize Anthropic client with API key
    - Implement generate_article method with structured prompts
    - Target 10-15 minute reading time (1500-2500 words)
    - _Requirements: 2.1, 2.2_
  
  - [ ] 5.2 Implement article structure generation
    - Generate title, summary, and structured sections
    - Format content as Markdown
    - Calculate reading time
    - _Requirements: 2.3_
  
  - [ ] 5.3 Implement citation generation and validation
    - Extract citations from generated content
    - Validate citations reference actual source URLs
    - _Requirements: 2.4_
  
  - [ ] 5.4 Add retry logic with exponential backoff
    - Retry failed generation attempts (max 3 attempts)
    - Implement exponential backoff (1s, 2s, 4s)
    - _Requirements: 2.6_
  
  - [ ]* 5.5 Write property test for article generation completeness
    - **Property 3: Article generation completeness**
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.4**
  
  - [ ]* 5.6 Write property test for retry with exponential backoff
    - **Property 4: Retry with exponential backoff**
    - **Validates: Requirements 2.6**

- [ ] 6. Implement content pipeline - Content validator
  - [ ] 6.1 Create ContentValidator class
    - Implement validate_article method
    - Check word count (minimum 1500 words)
    - Check citations (at least 1 citation)
    - Check structure (introduction, body, conclusion)
    - _Requirements: 10.1, 10.2, 10.3_
  
  - [ ] 6.2 Add validation metrics tracking
    - Track word count, citation count, generation time
    - Return ValidationResult with errors and warnings
    - _Requirements: 10.4, 10.5_
  
  - [ ]* 6.3 Write property test for article quality validation
    - **Property 22: Article quality validation**
    - **Validates: Requirements 10.1, 10.2, 10.3**
  
  - [ ]* 6.4 Write property test for validation rejection
    - **Property 23: Validation rejection**
    - **Validates: Requirements 10.4**
  
  - [ ]* 6.5 Write property test for metrics tracking
    - **Property 24: Metrics tracking**
    - **Validates: Requirements 10.5**

- [ ] 7. Implement content pipeline - Scheduler and orchestration
  - [ ] 7.1 Create ArticleScheduler class
    - Implement generate_daily_article method
    - Orchestrate scraping → generation → validation → storage pipeline
    - _Requirements: 4.1, 4.3_
  
  - [ ] 7.2 Implement topic selection and uniqueness checking
    - Create curated topic list for Indian history
    - Check topic uniqueness against existing articles
    - _Requirements: 4.4, 4.5_
  
  - [ ] 7.3 Add comprehensive logging
    - Log all pipeline operations with timestamps
    - Log errors with context and stack traces
    - Use structured logging with severity levels
    - _Requirements: 11.1, 11.3, 11.4_
  
  - [ ]* 7.4 Write property test for topic uniqueness
    - **Property 11: Topic uniqueness**
    - **Validates: Requirements 4.4**

- [ ] 8. Checkpoint - Ensure content pipeline tests pass
  - Ensure all content pipeline tests pass, ask the user if questions arise.

- [ ] 9. Implement backend API - Article service
  - [ ] 9.1 Create ArticleService class with Supabase integration
    - Initialize Supabase client
    - Implement save_article method (store in PostgreSQL with JSONB content)
    - Implement get_daily_article method
    - Implement get_article_by_id method
    - Implement get_article_by_date method
    - Implement list_articles method with pagination
    - Upload article images to Supabase Storage
    - _Requirements: 3.1, 3.2, 3.3, 4.1, 4.2, 9.3_
  
  - [ ] 9.2 Add article storage management
    - Store article content as JSONB in PostgreSQL
    - Handle image uploads to Supabase Storage
    - Generate and return public URLs for images
    - Handle storage errors gracefully
    - _Requirements: 3.1_
  
  - [ ]* 9.3 Write property test for date-based ordering
    - **Property 7: Date-based ordering**
    - **Validates: Requirements 3.4**
  
  - [ ]* 9.4 Write property test for storage validation
    - **Property 8: Storage validation**
    - **Validates: Requirements 3.5**
  
  - [ ]* 9.5 Write property test for one daily article per day
    - **Property 9: One daily article per day**
    - **Validates: Requirements 4.1**
  
  - [ ]* 9.6 Write property test for daily article updates
    - **Property 10: Daily article updates with date**
    - **Validates: Requirements 4.3**

- [ ] 10. Implement backend API - Search service with PostgreSQL full-text search
  - [ ] 10.1 Create SearchService class with PostgreSQL tsvector integration
    - Implement search method using PostgreSQL full-text search (tsvector, ts_rank)
    - Return results ranked by relevance
    - Support multi-field search (title, content, tags)
    - _Requirements: 7.1, 7.2, 7.3, 7.6_
  
  - [ ] 10.2 Implement autocomplete with search suggestions
    - Implement autocomplete method with prefix matching using LIKE or pg_trgm
    - Query search_suggestions table
    - Return top 10 suggestions ordered by frequency
    - _Requirements: 7.1_
  
  - [ ] 10.3 Implement search suggestion extraction
    - Extract terms from article titles, tags, and content
    - Use NER for person names, event names, periods
    - Update search_suggestions table on article creation
    - _Requirements: 7.1, 7.6_
  
  - [ ] 10.4 Add result highlighting and snippets
    - Highlight matching terms in search results using ts_headline
    - Generate relevant snippets from content
    - _Requirements: 7.4_
  
  - [ ]* 10.5 Write property test for search result relevance
    - **Property 12: Search result relevance**
    - **Validates: Requirements 7.2**
  
  - [ ]* 10.6 Write property test for search result ordering
    - **Property 13: Search result ordering**
    - **Validates: Requirements 7.3**
  
  - [ ]* 10.7 Write property test for multi-field search
    - **Property 14: Multi-field search**
    - **Validates: Requirements 7.6**
  
  - [ ]* 10.8 Write property test for autocomplete prefix matching
    - **Property 33: Autocomplete prefix matching**
    - **Validates: Requirements 7.1**
  
  - [ ]* 10.9 Write property test for autocomplete performance
    - **Property 34: Autocomplete performance**
    - **Validates: Requirements 7.1**
  
  - [ ]* 10.10 Write property test for search suggestion updates
    - **Property 36: Search suggestion updates**
    - **Validates: Requirements 7.1**

- [ ] 11. Implement backend API - Semantic search with pgvector (optional)
  - [ ] 11.1 Enable pgvector extension in Supabase
    - Enable pgvector extension in Supabase dashboard or via SQL
    - Verify extension is available
    - _Requirements: 7.2, 7.6_
  
  - [ ] 11.2 Add embedding generation using Claude or OpenAI
    - Implement generate_embedding method
    - Support both Claude and OpenAI embedding models
    - _Requirements: 7.2, 7.6_
  
  - [ ] 11.3 Implement semantic search with pgvector cosine similarity
    - Implement semantic_search method using pgvector operators
    - Use IVFFlat index for efficient similarity search
    - Return semantically similar articles
    - _Requirements: 7.2, 7.6_
  
  - [ ] 11.4 Add hybrid search combining PostgreSQL full-text and pgvector
    - Merge full-text and semantic search results
    - Deduplicate and rank combined results
    - _Requirements: 7.2, 7.3_
  
  - [ ]* 11.5 Write property test for semantic search similarity
    - **Property 35: Semantic search similarity**
    - **Validates: Requirements 7.2, 7.6**

- [ ] 12. Implement backend API - Authentication service with Supabase Auth
  - [ ] 12.1 Create AuthService class with Supabase Auth integration
    - Initialize Supabase client for auth operations
    - Implement register_user method using Supabase Auth signup
    - Implement login_user method using Supabase Auth signin
    - Supabase handles email validation and password hashing automatically
    - _Requirements: 12.1, 12.4, 12.5, 12.6_
  
  - [ ] 12.2 Add OAuth support via Supabase Auth
    - Implement oauth_login method for Google (handled by Supabase)
    - Implement oauth_login method for Facebook (handled by Supabase)
    - Supabase manages OAuth flow and token exchange
    - _Requirements: 12.2, 12.3_
  
  - [ ] 12.3 Implement token refresh and logout
    - Implement refresh_token method using Supabase Auth
    - Implement logout method (Supabase session termination)
    - _Requirements: 12.7_
  
  - [ ] 12.4 Add user profile management
    - Implement get_current_user method
    - Sync user data with user_profiles table
    - _Requirements: 12.5_
  
  - [ ]* 12.5 Write property test for email validation
    - **Property 27: Email validation**
    - **Validates: Requirements 12.4**
  
  - [ ]* 12.6 Write property test for session creation
    - **Property 28: Session creation**
    - **Validates: Requirements 12.5**
  
  - [ ]* 12.7 Write property test for password security
    - **Property 29: Password security**
    - **Validates: Requirements 12.6**
  
  - [ ]* 12.8 Write property test for logout session termination
    - **Property 30: Logout session termination**
    - **Validates: Requirements 12.7**

- [ ] 13. Implement backend API - Like service with Row-Level Security
  - [ ] 13.1 Create LikeService class with Supabase integration
    - Implement like_article method
    - Implement unlike_article method (toggle behavior)
    - Implement is_liked method
    - Implement get_user_likes method
    - Implement get_article_like_count method
    - Row-Level Security policies ensure users can only manage their own likes
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6_
  
  - [ ]* 13.2 Write property test for like toggle behavior
    - **Property 31: Like toggle behavior**
    - **Validates: Requirements 13.2, 13.3**
  
  - [ ]* 13.3 Write property test for like persistence
    - **Property 32: Like persistence**
    - **Validates: Requirements 13.5, 13.6**

- [ ] 14. Implement backend API - FastAPI endpoints
  - [ ] 14.1 Create FastAPI application and router setup
    - Initialize FastAPI app
    - Set up CORS middleware
    - Add request logging middleware
    - Create API routers for articles, auth, likes
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  
  - [ ] 14.2 Implement article endpoints
    - GET /api/v1/articles/daily
    - GET /api/v1/articles/{id}
    - GET /api/v1/articles (with pagination)
    - GET /api/v1/articles/search?q=...
    - GET /api/v1/articles/search/autocomplete?q=...
    - GET /api/v1/articles/search/semantic?q=... (optional)
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  
  - [ ] 14.3 Implement authentication endpoints
    - POST /api/v1/auth/register
    - POST /api/v1/auth/login
    - POST /api/v1/auth/oauth/google
    - POST /api/v1/auth/oauth/facebook
    - POST /api/v1/auth/refresh
    - POST /api/v1/auth/logout
    - _Requirements: 12.1, 12.2, 12.3, 12.7_
  
  - [ ] 14.4 Implement like endpoints (authenticated via Supabase Auth)
    - POST /api/v1/articles/{id}/like
    - DELETE /api/v1/articles/{id}/like
    - GET /api/v1/users/me/likes
    - Add Supabase JWT authentication middleware
    - Verify user identity from Supabase Auth token
    - _Requirements: 13.1, 13.2, 13.6, 13.7_
  
  - [ ] 14.5 Add error handling and response formatting
    - Implement error response format
    - Add HTTP status codes (400, 401, 403, 404, 429, 500, 503)
    - Add descriptive error messages
    - _Requirements: 9.6_
  
  - [ ] 14.6 Implement rate limiting
    - Add rate limiter middleware (100 requests per minute per IP)
    - Return 429 Too Many Requests when exceeded
    - _Requirements: 9.7_
  
  - [ ]* 14.7 Write property test for pagination consistency
    - **Property 20: Pagination consistency**
    - **Validates: Requirements 9.3**
  
  - [ ]* 14.8 Write property test for API response format
    - **Property 21: API response format**
    - **Validates: Requirements 9.5, 9.6**

- [ ] 15. Checkpoint - Ensure backend API tests pass
  - Ensure all backend API tests pass, ask the user if questions arise.

- [ ] 16. Implement mobile app - Project setup and dependencies
  - [ ] 16.1 Create Flutter project structure
    - Initialize Flutter project in bharatverse_app/
    - Set up directory structure: lib/models/, lib/services/, lib/screens/, lib/widgets/, lib/state/
    - _Requirements: 5.1, 5.2, 6.1_
  
  - [ ] 16.2 Add dependencies to pubspec.yaml
    - Add provider, supabase_flutter, http, shared_preferences, sqflite, cached_network_image
    - Supabase Flutter SDK includes auth and storage clients
    - _Requirements: 5.1, 8.1, 12.2, 12.3_
  
  - [ ] 16.3 Configure Android and iOS settings
    - Set minimum SDK versions (Android 8.0+, iOS 13.0+)
    - Configure Supabase URL and anon key in app
    - Add deep link configuration for OAuth redirects
    - Add internet permissions
    - _Requirements: 12.2, 12.3_

- [ ] 17. Implement mobile app - Data models and API client
  - [ ] 17.1 Create Dart data models
    - Create Article model matching backend schema
    - Create User model
    - Create AuthResponse model
    - Add JSON serialization/deserialization
    - _Requirements: 3.3, 5.1, 12.5_
  
  - [ ] 17.2 Initialize Supabase client in Flutter app
    - Initialize Supabase client with URL and anon key
    - Configure auth persistence
    - Set up deep link handling for OAuth
    - _Requirements: 12.2, 12.3_
  
  - [ ] 17.3 Create ApiClient class for custom endpoints
    - Implement getDailyArticle method (calls FastAPI)
    - Implement getArticle method
    - Implement listArticles method with pagination
    - Implement searchArticles method
    - Implement getAutocompleteSuggestions method
    - Implement semanticSearch method (optional)
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  
  - [ ] 17.4 Add authentication methods using Supabase Auth
    - Implement register method using Supabase.auth.signUp
    - Implement login method using Supabase.auth.signInWithPassword
    - Implement signInWithGoogle using Supabase.auth.signInWithOAuth
    - Implement signInWithFacebook using Supabase.auth.signInWithOAuth
    - Implement signOut method
    - _Requirements: 12.1, 12.2, 12.3, 12.7_
  
  - [ ] 17.5 Add like methods using Supabase client
    - Implement likeArticle method (direct Supabase insert)
    - Implement unlikeArticle method (direct Supabase delete)
    - Implement getUserLikes method (direct Supabase query)
    - Row-Level Security ensures data access control
    - _Requirements: 13.1, 13.2, 13.6_

- [ ] 18. Implement mobile app - Local cache and storage
  - [ ] 18.1 Create ArticleCache class with SQLite
    - Set up local SQLite database
    - Implement cacheArticle method
    - Implement getCachedArticle method
    - Implement getCachedArticles method
    - Implement clearOldCache method (keep last 7 days)
    - _Requirements: 8.1, 8.2, 8.3, 8.4_
  
  - [ ] 18.2 Use Supabase Auth for token storage
    - Supabase Flutter SDK handles secure token storage automatically
    - Tokens persisted across app restarts
    - No need for flutter_secure_storage (handled by Supabase)
    - _Requirements: 12.5_
  
  - [ ]* 18.3 Write property test for view-triggered caching
    - **Property 15: View-triggered caching**
    - **Validates: Requirements 8.1**
  
  - [ ]* 18.4 Write property test for offline article access
    - **Property 16: Offline article access**
    - **Validates: Requirements 8.2**
  
  - [ ]* 18.5 Write property test for minimum cache retention
    - **Property 17: Minimum cache retention**
    - **Validates: Requirements 8.3**
  
  - [ ]* 18.6 Write property test for LRU cache eviction
    - **Property 18: LRU cache eviction**
    - **Validates: Requirements 8.4**
  
  - [ ]* 18.7 Write property test for cache synchronization
    - **Property 19: Cache synchronization**
    - **Validates: Requirements 8.5**

- [ ] 19. Implement mobile app - State management with Supabase
  - [ ] 19.1 Create ArticleState with Provider
    - Implement fetchDailyArticle method
    - Implement fetchArticles method with pagination
    - Implement searchArticles method
    - Add loading and error state management
    - _Requirements: 4.2, 5.1, 6.1, 7.1_
  
  - [ ] 19.2 Create AuthState with Provider and Supabase Auth
    - Implement register method using Supabase Auth
    - Implement login method using Supabase Auth
    - Implement loginWithGoogle method using Supabase OAuth
    - Implement loginWithFacebook method using Supabase OAuth
    - Implement logout method
    - Listen to Supabase auth state changes
    - Manage authentication state automatically
    - _Requirements: 12.1, 12.2, 12.3, 12.7_
  
  - [ ] 19.3 Create LikeState with Provider and Supabase
    - Implement toggleLike method (direct Supabase operations)
    - Implement fetchUserLikes method
    - Implement isLiked method
    - Sync with Supabase automatically
    - _Requirements: 13.1, 13.2, 13.3, 13.4_

- [ ] 20. Implement mobile app - UI screens
  - [ ] 20.1 Create HomeScreen
    - Display daily article prominently (DailyArticleCard)
    - Show list of past articles (ArticleListView)
    - Add bottom navigation bar
    - Handle loading and error states
    - _Requirements: 4.2, 5.1, 6.1_
  
  - [ ] 20.2 Create ArticleDetailScreen
    - Display article header (title, date, reading time)
    - Render article content as Markdown
    - Show citations section
    - Add like button with toggle behavior
    - Support smooth scrolling
    - Display images inline
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 13.1, 13.4_
  
  - [ ] 20.3 Create SearchScreen
    - Add search bar with autocomplete
    - Display search results list
    - Show article metadata in results
    - Highlight matching terms
    - Handle empty results with suggestions
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_
  
  - [ ] 20.4 Create AuthScreen with Supabase Auth
    - Add email/password login form
    - Add registration link
    - Add Google OAuth button (Supabase handles flow)
    - Add Facebook OAuth button (Supabase handles flow)
    - Handle authentication errors
    - _Requirements: 12.1, 12.2, 12.3, 12.8_
  
  - [ ] 20.5 Create ProfileScreen with liked articles
    - Display user's liked articles list
    - Support navigation to article details
    - Add logout button
    - _Requirements: 13.6_

- [ ] 21. Implement mobile app - UI widgets
  - [ ] 21.1 Create DailyArticleCard widget
    - Display featured article with image, title, summary
    - Add tap navigation to article detail
    - _Requirements: 4.2, 5.1_
  
  - [ ] 21.2 Create ArticleListTile widget
    - Display compact article info (title, date, reading time)
    - Add tap navigation to article detail
    - _Requirements: 6.1, 6.2, 6.3_
  
  - [ ] 21.3 Create ArticleContentView widget
    - Render Markdown content with proper typography
    - Support images, headings, lists, links
    - _Requirements: 5.2_
  
  - [ ] 21.4 Create LikeButton widget
    - Animated heart icon
    - Toggle behavior (like/unlike)
    - Visual indication of liked state
    - Prompt login if not authenticated
    - _Requirements: 13.1, 13.2, 13.4, 13.7_

- [ ] 22. Implement mobile app - Offline support
  - [ ] 22.1 Add network connectivity detection
    - Detect online/offline state
    - Show offline indicator in UI
    - _Requirements: 8.2_
  
  - [ ] 22.2 Implement cache-first data loading
    - Try cache first, then network
    - Display cached articles when offline
    - Sync with server when online
    - _Requirements: 8.2, 8.5_
  
  - [ ] 22.3 Add error handling for network failures
    - Display user-friendly error messages
    - Offer retry option
    - Fallback to cached content
    - _Requirements: 12.8_

- [ ] 23. Checkpoint - Ensure mobile app tests pass
  - Ensure all mobile app tests pass, ask the user if questions arise.

- [ ] 24. Implement error handling and logging
  - [ ] 24.1 Add structured logging to backend
    - Use Python logging with JSON formatter
    - Add log levels (DEBUG, INFO, WARNING, ERROR)
    - Log all API requests with response times
    - _Requirements: 11.1, 11.3, 11.4_
  
  - [ ] 24.2 Add error logging to content pipeline
    - Log scraping errors with context
    - Log LLM generation errors
    - Log validation errors
    - _Requirements: 11.1_
  
  - [ ] 24.3 Add error handling to mobile app
    - Display user-friendly error messages
    - Log errors locally for debugging
    - Handle network, authentication, and cache errors
    - _Requirements: 12.8_
  
  - [ ]* 24.4 Write property test for error logging completeness
    - **Property 25: Error logging completeness**
    - **Validates: Requirements 11.1, 11.3**
  
  - [ ]* 24.5 Write property test for log level structure
    - **Property 26: Log level structure**
    - **Validates: Requirements 11.4**

- [ ] 25. Integration testing and end-to-end flows
  - [ ]* 25.1 Write integration test for complete content pipeline
    - Test scraping → generation → validation → storage flow
    - Verify article appears in API and mobile app
    - _Requirements: 1.1, 2.1, 3.1, 9.1_
  
  - [ ]* 25.2 Write integration test for authentication flow
    - Test registration → login → authenticated API calls → logout
    - Verify token handling and session management
    - _Requirements: 12.1, 12.5, 12.7_
  
  - [ ]* 25.3 Write integration test for like flow
    - Test like → unlike → fetch user likes
    - Verify persistence across app restarts
    - _Requirements: 13.1, 13.2, 13.5, 13.6_
  
  - [ ]* 25.4 Write integration test for search flow
    - Test article indexing → search → autocomplete → results
    - Verify FTS5 and semantic search (if implemented)
    - _Requirements: 7.1, 7.2, 7.3_
  
  - [ ]* 25.5 Write integration test for offline flow
    - Test article view → cache → offline access → online sync
    - Verify cache eviction and retention
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [ ] 26. Deployment preparation
  - [ ] 26.1 Create deployment scripts for backend
    - Create Dockerfile for FastAPI app
    - Create docker-compose.yml for local development
    - Add environment variable templates (.env.example with Supabase keys)
    - _Requirements: All backend requirements_
  
  - [ ] 26.2 Document Supabase setup process
    - Create guide for setting up Supabase project
    - Document database schema deployment
    - Document Row-Level Security policy setup
    - Document OAuth provider configuration
    - Document Storage bucket setup
    - _Requirements: 3.1, 12.2, 12.3_
  
  - [ ] 26.3 Configure mobile app for production
    - Set production API endpoint
    - Configure Supabase production URL and keys
    - Set up deep link configuration for OAuth
    - Set up app signing for Android and iOS
    - _Requirements: 9.1, 12.2, 12.3_
  
  - [ ] 26.4 Create documentation
    - API documentation (endpoints, request/response formats)
    - Setup instructions for local development with Supabase
    - Deployment guide for backend
    - Supabase configuration guide
    - Mobile app build and release guide
    - _Requirements: All requirements_

- [ ] 27. Final checkpoint - Complete system testing
  - Run all tests (unit, property, integration)
  - Verify all 36 correctness properties pass
  - Test complete user flows (registration → browse → search → like → offline)
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional test tasks and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Property tests validate universal correctness properties (minimum 100 iterations each)
- Unit tests validate specific examples and edge cases
- Integration tests validate end-to-end flows
- Checkpoints ensure incremental validation at major milestones
- All 36 correctness properties from the design document are covered by property-based tests
- Code cleanup tasks address existing files that need refactoring or removal
