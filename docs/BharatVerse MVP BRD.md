# BharatVerse MVP BRD (Updated)

## *Updated: 2/15/2026*
*Original: 2/28/2025*

---

## 1. Executive Summary

* **Description**: BharatVerse is a mobile-first app focused on delivering daily, curated historical articles on Indian history. Each article will be generated using AI (Anthropic Claude), with a focus on making history accessible and engaging through 10-15 minute reads.
* **MVP Goal**: Validate the core concept with a working prototype that demonstrates the content pipeline, mobile app, and basic user engagement features.
* **MVP Scope**: English-only content, basic authentication, article likes (no comments/sharing), offline reading support.

---

## 2. Business Objectives

* **Primary Goal**: Validate product-market fit with a functional MVP that delivers high-quality historical content.
* **MVP Revenue Model**: All content free (no subscription/paywall in MVP).
* **Target Audience**: History enthusiasts, students, and people interested in learning about India's rich cultural heritage.
* **Success Criteria**: User engagement (daily active users, reading completion rate, article likes).

---

## 3. MVP Scope

### In Scope for MVP
* Daily historical articles (10-15 minute reads)
* Content pipeline (Wikipedia + archive.org scraping + AI generation)
* Mobile app (Flutter for iOS and Android)
* User authentication (email/password + Google + Facebook OAuth)
* Article search with autocomplete and semantic similarity
* Article likes for future personalization
* Offline article access (last 7 days cached)
* Article browsing and navigation

### Out of Scope for MVP (Post-MVP)
* ❌ Multilingual support (English only in MVP)
* ❌ Comments and social sharing
* ❌ Subscription and payment system
* ❌ Push notifications
* ❌ Advanced personalization/recommendations
* ❌ Content management UI
* ❌ Analytics dashboard
* ❌ Reading history tracking

---

## 4. User Stories (MVP)

#### **User Story 1: Daily Article Feed**
* **As a user**, I want to see a new historical article every day so that I can learn about different aspects of Indian history regularly.
* **Acceptance Criteria**:
  * Users see one featured article each day
  * Article includes title, summary, content, images, and citations
  * Articles are 10-15 minute reads (1500-2500 words)

#### **User Story 2: Article Search**
* **As a user**, I want to search through articles so that I can find specific historical topics.
* **Acceptance Criteria**:
  * Search bar with autocomplete suggestions
  * Results ordered by relevance
  * Semantic search finds related content
  * Search by historical period, person names, event names

#### **User Story 3: User Registration and Login**
* **As a user**, I want to create an account and log in so that I can like articles and have a personalized experience.
* **Acceptance Criteria**:
  * Users can sign up using email/password
  * Users can sign in with Google OAuth
  * Users can sign in with Facebook OAuth
  * Secure password storage and JWT authentication

#### **User Story 4: Article Likes**
* **As a user**, I want to like articles I enjoy so that the app can learn my preferences.
* **Acceptance Criteria**:
  * Like button on each article
  * Toggle behavior (like/unlike)
  * View list of liked articles
  * Likes persist across sessions

#### **User Story 5: Offline Reading**
* **As a user**, I want to access recently viewed articles offline so that I can read without internet.
* **Acceptance Criteria**:
  * Articles cached locally after viewing
  * Last 7 days of articles available offline
  * Offline indicator in UI
  * Sync with server when online

#### **User Story 6: Article Navigation**
* **As a user**, I want to browse past articles so that I can explore historical content at my own pace.
* **Acceptance Criteria**:
  * List view of past articles
  * Articles ordered by publication date
  * Article metadata displayed (title, date, reading time)
  * Smooth scrolling and navigation

---

## 5. Functional Requirements (MVP)

#### **1. Content Curation and Scraping**
* **Description**: Automated content pipeline that scrapes, generates, and validates articles.
* **Requirements**:
  * Scrape Wikipedia and archive.org for historical content
  * Use Anthropic Claude to generate curated articles
  * Validate article quality (word count, citations, structure)
  * Store articles in SQLite database with JSON files
  * Generate one article per day

#### **2. Article Delivery**
* **Description**: REST API to serve articles to mobile app.
* **Requirements**:
  * FastAPI backend with REST endpoints
  * Get daily article, get article by ID, list articles (paginated)
  * Search articles with autocomplete and semantic similarity
  * Rate limiting (100 requests/minute per IP)
  * Response time < 2 seconds

#### **3. User Management**
* **Description**: Authentication and user account management.
* **Requirements**:
  * Email/password registration and login
  * Google OAuth integration
  * Facebook OAuth integration
  * JWT token-based authentication
  * Secure password hashing (bcrypt)
  * Password reset functionality

#### **4. Search Functionality**
* **Description**: Advanced search with autocomplete and semantic similarity.
* **Requirements**:
  * SQLite FTS5 for full-text search (BM25 ranking)
  * Autocomplete suggestions from pre-computed terms
  * Semantic search using article embeddings
  * Hybrid search combining both approaches
  * Search by title, content, tags, person names, events

#### **5. Mobile App**
* **Description**: Flutter-based cross-platform mobile application.
* **Requirements**:
  * Support Android 8.0+ and iOS 13.0+
  * Display daily article prominently
  * Article detail view with markdown rendering
  * Search interface with autocomplete
  * User authentication screens
  * Offline article caching (last 7 days)
  * Like button with toggle behavior

---

## 6. Non-Functional Requirements (MVP)

* **Performance**: 
  * Article load time < 1 second (cached) or < 3 seconds (network)
  * API response time < 2 seconds
  * App launch time < 2 seconds
* **Scalability**: Handle 1,000 concurrent users (MVP scale)
* **Security**: 
  * HTTPS only
  * JWT token authentication
  * Password hashing with bcrypt
  * Input validation on all endpoints
* **Availability**: 95% uptime (MVP target)
* **Compatibility**: Android 8.0+, iOS 13.0+, minimum 2GB RAM

---

## 7. Technical Requirements (MVP)

* **Platform**: Mobile-first (iOS, Android via Flutter)
* **Backend Stack**: 
  * Python 3.12+
  * FastAPI for REST API
  * SQLite for database (with FTS5 for search)
  * Anthropic Claude for article generation
  * Playwright for web scraping
* **Mobile Stack**:
  * Flutter SDK 3.x
  * Provider/Riverpod for state management
  * sqflite for local caching
  * flutter_secure_storage for tokens
* **Infrastructure**: Single server deployment (VPS or cloud instance)

---

## 8. Milestones & Timeline (MVP)

1. **Phase 1: Backend Foundation** (2 weeks)
   * Content pipeline (scraping + LLM generation + validation)
   * Database schema and models
   * REST API endpoints

2. **Phase 2: Mobile App** (2 weeks)
   * UI screens (home, article detail, search, auth)
   * State management and API integration
   * Offline caching

3. **Phase 3: Testing & Polish** (1 week)
   * Unit tests and property-based tests
   * Integration testing
   * Bug fixes and performance optimization

4. **Phase 4: Beta Release** (1 week)
   * Deploy backend
   * Release beta to TestFlight/Play Store Beta
   * Collect user feedback

**Total MVP Timeline**: 6 weeks

---

## 9. Success Metrics (MVP)

* **User Engagement**:
  * Daily active users (DAU)
  * Article completion rate (% who read to end)
  * Average reading time per article
  * Articles liked per user
* **Technical Metrics**:
  * API response times
  * App crash rate
  * Article generation success rate
* **User Feedback**:
  * App store rating (target 4.0+)
  * User feedback and feature requests

---

## 10. Risks and Assumptions (MVP)

* **Risks**:
  * AI-generated content quality and accuracy
  * Copyright issues with scraped content
  * User adoption and retention
  * API rate limits (Anthropic Claude)
* **Assumptions**:
  * Sufficient interest in Indian history content
  * English-only content acceptable for MVP
  * Users willing to create accounts for likes feature
  * SQLite sufficient for MVP scale (< 10,000 users)

---

## 11. Post-MVP Roadmap

**Version 1.1** (3 months post-MVP):
* Multilingual support (Hindi, Marathi, Sanskrit)
* Push notifications for daily articles
* Social sharing (WhatsApp, Facebook)

**Version 1.2** (6 months post-MVP):
* Comments and user discussions
* Reading history and progress tracking
* Personalized recommendations based on likes

**Version 2.0** (9 months post-MVP):
* Subscription and premium content
* Payment integration (Razorpay, Stripe)
* Content management dashboard
* Advanced analytics

---

## Changes from Original BRD

1. **Scope Reduction**: Focused on core MVP features, deferred social features, multilingual, subscriptions
2. **Tech Stack Clarification**: Specified Anthropic Claude (not OpenAI), SQLite (not Firebase), Flutter (confirmed)
3. **Search Enhancement**: Added autocomplete and semantic search capabilities
4. **Timeline Adjustment**: Realistic 6-week MVP timeline vs. original 1-2 months
5. **Success Metrics**: Focused on engagement metrics vs. revenue (no subscription in MVP)
6. **Architecture**: Detailed backend (FastAPI + SQLite) and mobile (Flutter) stack
