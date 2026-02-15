# BharatVerse Content Pipeline

This directory contains the content generation pipeline for BharatVerse MVP.

## Overview

The content pipeline scrapes historical content from authoritative sources (Wikipedia, archive.org), uses AI (Anthropic Claude) to generate curated 10-15 minute read articles, validates quality, and stores them for the mobile app.

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

From the project root (`BharatVerse/`):

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
pip install -r scrapper/requirements.txt
```

### 3. Install Browser Binaries (for Playwright)

```bash
playwright install
```

### 4. Configure Environment Variables

Create a `.env` file in the project root (`BharatVerse/.env`) with:

```env
GEMINI_API_KEY=your_gemini_api_key_here
```

## Usage

Run the content pipeline:

```bash
python scrapper/scrapper_main.py
```

## Project Structure

```
scrapper/
├── model/
│   └── article.py          # Pydantic models (Article, Citation, Section, ScrapedContent)
├── data/
│   └── web-sources.yaml    # Configuration for scraping sources
├── scrapper_main.py        # Main entry point for content pipeline
├── requirements.txt        # Python dependencies
└── README.md              # This file
```

## Data Models

### Article
Complete historical article with all metadata:
- `id`: Unique identifier (format: art_YYYYMMDD_NNN)
- `title`, `summary`, `content`: Article text
- `sections`: List of structured sections
- `citations`: List of source references
- `date`, `reading_time_minutes`, `author`, `tags`
- `image_url`, `created_at`, `updated_at`

### ScrapedContent
Raw content extracted from sources before LLM processing:
- `source_url`, `title`, `raw_text`
- `images`, `metadata`, `scraped_at`

### Citation
Reference to source material:
- `text`, `source_url`, `source_name`, `accessed_date`

### Section
Structured section within an article:
- `heading`, `content`, `order`

## Pipeline Components

The pipeline consists of four main components:

1. **WebScraper**: Fetches content from Wikipedia and archive.org
2. **ArticleGenerator**: Uses Anthropic Claude to generate curated articles
3. **ContentValidator**: Ensures articles meet quality standards
4. **ArticleScheduler**: Orchestrates daily article generation

See `.kiro/specs/bharatverse-mvp/design.md` for detailed component interfaces.
