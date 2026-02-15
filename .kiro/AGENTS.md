# AGENTS.md - BharatVerse Codebase Guide

This document provides essential information for AI agents working within the BharatVerse repository. It outlines project structure, commands, conventions, and important considerations to facilitate effective contributions.

## Project Overview

The BharatVerse repository contains two primary sub-projects:
1.  **`bharatverse_app`**: A cross-platform mobile application developed using Flutter.
2.  **`scrapper`**: A Python-based web scraping application.

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

## `scrapper` (Python Scraper)

### Overview
This project contains a Python-based web scraper.

### Essential Commands

**Setup:**
1.  **Create a virtual environment:** From the project root (`BharatVerse/`):
    ```bash
    python -m venv .venv
    source .venv/bin/activate
    ```
2.  **Install dependencies:** From the project root, ensure virtual environment is active, then install required packages:
    ```bash
    pip install -r scrapper/requirements.txt
    ```
3.  **Install browser binaries:** The `crawl4ai` library (used indirectly via `playwright`) requires browser binaries. Run:
    ```bash
    playwright install
    ```

**Run the scraper:**
To run the main scraper logic, from the project root (`BharatVerse/`):
```bash
python scrapper/scrapper_main.py
```

**Run agent-specific logic:** (If `agent_main.py` is intended as a separate entry point)
From the project root (`BharatVerse/`):
```bash
python scrapper/agent_main.py
```

### Environment Variables
The scraper requires an API key for the Anthropic Claude LLM.
1.  Create a `.env` file in the `BharatVerse/` root directory.
2.  Add the API key:
    ```
    ANTHROPIC_CLAUDE_API_KEY=your_api_key_here
    ```

### Code Organization
*   `scrapper_main.py`: Main script for the scraping logic.
*   `agent_main.py`: Possibly an alternative or agent-specific entry point for scraping.
*   `model/`: Contains Pydantic models for data structures, e.g., `article.py` defines the `Article` model.
*   `data/web-sources.yaml`: Likely configuration file for defining web sources to scrape.

### Naming Conventions and Style
The Python code generally follows PEP 8 conventions:
*   Functions and variables use `snake_case`.
*   Classes use `CamelCase` (e.g., `Article`).

### Testing Approach
No explicit testing framework or test files were observed within the `scrapper` directory.

## General Gotchas and Patterns

*   **Virtual Environments:** Python projects (`scrapper`) utilize virtual environments for dependency management. Always activate the virtual environment before installing packages or running scripts.
*   **Environment Variables:** Sensitive information like API keys are loaded via `.env` files using `python-dotenv`. Ensure the `.env` file is set up correctly in the project root.
*   **Asynchronous Operations:** The Python scraper uses `asyncio` for asynchronous operations.
*   **Web Interaction:** The Python scraper uses `playwright` for browser automation and `langchain_community` for integrating with external APIs like Wikipedia.
*   **Data Models:** Pydantic is used in the Python scraper for data validation and serialization of models like `Article`.
