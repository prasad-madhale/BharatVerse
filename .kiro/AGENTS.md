# AGENTS.md - BharatVerse Codebase Guide

This document provides essential information for AI agents working within the BharatVerse repository. It outlines project structure, commands, conventions, and important considerations to facilitate effective contributions.

## Project Overview

The BharatVerse repository is a monorepo containing three primary services:
1.  **`bharatverse_app`**: A cross-platform mobile application developed using Flutter.
2.  **`backend`**: A FastAPI-based REST API server.
3.  **`scrapper`**: A Python-based content generation pipeline.

## `bharatverse_app` (Flutter Application)

### Overview
This is a standard Flutter application.

### Essential Commands

**Setup:**
To fetch project dependencies, navigate to the `bharatverse_app` directory and run:
```bash
flutter pub get
```

**Run the application:**
From the `bharatverse_app` directory:
```bash
flutter run
```

**Run tests:**
From the `bharatverse_app` directory:
```bash
flutter test
```

### Code Organization
The project follows a standard Flutter directory structure. Key directories include:
*   `lib/`: Contains the main application source code. `lib/main.dart` is the entry point.
*   `test/`: Contains unit and widget tests. `test/widget_test.dart` is an example widget test.

### Naming Conventions and Style
The codebase adheres to standard Dart and Flutter naming conventions:
*   Classes and type names use `CamelCase` (e.g., `MyApp`, `MyHomePage`).
*   Private members are prefixed with an underscore (`_lowerCamelCase`) (e.g., `_MyHomePageState`, `_counter`).
*   Variables and functions use `lowerCamelCase`.

### Testing Approach
Widget testing is implemented using the `flutter_test` package. Tests are located in the `test/` directory.

## Testing

### Backend and Scrapper Tests
From the project root with virtual environment activated:
```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=backend --cov=scrapper

# Run property-based tests only
pytest -m property_test
```

### Mobile Tests
From the `bharatverse_app` directory:
```bash
flutter test

# With coverage
flutter test --coverage
```

## `scrapper` (Python Content Pipeline)

### Overview
This project contains the content generation pipeline that scrapes historical content and uses LLM to generate curated articles.

### Essential Commands

**Setup:**
1.  **Create a virtual environment:** From the project root (`BharatVerse/`):
    ```bash
    python3.12 -m venv .venv
    source .venv/bin/activate  # On Windows: .venv\Scripts\activate
    ```
2.  **Install dependencies:** From the project root, ensure virtual environment is active:
    ```bash
    pip install -r scrapper/requirements.txt
    ```
3.  **Install browser binaries:** The scraper uses `playwright` for web scraping:
    ```bash
    playwright install
    ```

**Run the scraper:**
From the project root (`BharatVerse/`):
```bash
python scrapper/scrapper_main.py
```

### Environment Variables
The scraper requires an LLM API key. Create a `.env` file in the `BharatVerse/` root directory:
```
LLM_PROVIDER=gemini
GEMINI_API_KEY=your_api_key_here
```

Supported providers: `gemini` (FREE, default), `anthropic`, `openai`, `groq`

### Code Organization
*   `scrapper_main.py`: Main script for the content pipeline.
*   `model/`: Contains Pydantic models for data structures, e.g., `article.py` defines the `Article` model.
*   `data/web-sources.yaml`: Configuration file for defining web sources to scrape.

### Naming Conventions and Style
The Python code follows PEP 8 conventions:
*   Functions and variables use `snake_case`.
*   Classes use `CamelCase` (e.g., `Article`).

## `backend` (FastAPI REST API)

### Overview
FastAPI-based REST API that serves articles to the mobile app, handles authentication, search, and user likes.

### Essential Commands

**Setup:**
1.  **Activate virtual environment:** (same as scrapper)
    ```bash
    source .venv/bin/activate  # On Windows: .venv\Scripts\activate
    ```
2.  **Install dependencies:**
    ```bash
    pip install -r backend/requirements.txt
    ```
3.  **Initialize database:**
    ```bash
    python backend/init_db.py
    ```

**Run the API server:**
Development mode with hot reload:
```bash
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```

Production mode:
```bash
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --workers 4
```

**API Documentation:**
When running, visit:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

### Environment Variables
Add to `.env` file in project root:
```
JWT_SECRET_KEY=your_secret_key_here
DATABASE_PATH=./bharatverse.db
ARTICLES_STORAGE_PATH=./articles
```

Generate JWT secret: `openssl rand -hex 32`

### Code Organization
*   `main.py`: FastAPI application entry point.
*   `api/`: API routers and endpoints (articles, auth, search, likes).
*   `services/`: Business logic layer.
*   `models/`: Data models and Pydantic schemas.
*   `database/`: Database operations and queries.
*   `utils/`: Utility functions (JWT, password hashing, validation).
*   `config.py`: Configuration management.

### Naming Conventions and Style
Follows PEP 8 conventions:
*   Functions and variables use `snake_case`.
*   Classes use `CamelCase`.
*   Async functions preferred for I/O operations.

### Testing Approach
No explicit testing framework or test files were observed within the `scrapper` directory.

## General Gotchas and Patterns

*   **Python Version:** This project requires Python 3.12+. Use `python3.12 -m venv .venv` when creating the virtual environment.
*   **Shared Virtual Environment:** Backend and scrapper share the same `.venv` at the project root.
*   **Virtual Environments:** Always activate the virtual environment before installing packages or running Python scripts.
*   **Environment Variables:** Sensitive information like API keys are loaded via `.env` files using `python-dotenv`. Ensure the `.env` file is set up correctly in the project root.
*   **Database Location:** SQLite database (`bharatverse.db`) and article storage (`articles/`) are at the project root.
*   **Asynchronous Operations:** The Python backend uses `asyncio` for asynchronous operations.
*   **Web Interaction:** The scraper uses `playwright` for browser automation and `langchain_community` for Wikipedia integration.
*   **Data Models:** Pydantic is used throughout for data validation and serialization.
*   **API Documentation:** When backend is running, interactive API docs are available at `/docs` and `/redoc` endpoints.
