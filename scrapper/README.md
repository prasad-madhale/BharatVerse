# Web Scraper for BharatVerse

LLM-optimized web scraper using Crawl4AI with extensible source architecture.

## Quick Start

```python
from scrapper import WebScraper

async def get_content(topic: str):
    scraper = WebScraper()
    
    # Scrape from all sources
    contents = await scraper.search_and_scrape(topic)
    
    # Scrape from specific sources
    contents = await scraper.search_and_scrape(
        topic, 
        sources=["wikipedia"]
    )
    
    # Scrape multiple pages per source
    contents = await scraper.search_and_scrape(
        topic,
        max_pages_per_source=3
    )
    
    return contents

# Use in your application
contents = await get_content("Mauryan Empire")
for content in contents:
    print(f"{content.title}: {len(content.raw_text)} chars")
```

## Development Setup

### Prerequisites
- Python 3.9+
- pip

### Installation

```bash
# Navigate to scrapper directory
cd scrapper

# Install all dependencies (includes test dependencies)
pip install -r requirements.txt
```

This installs:
- Core dependencies: `crawl4ai`, `wikipedia`, `internetarchive`, `pydantic`
- Test dependencies: `pytest`, `pytest-asyncio`
- LLM providers: `google-generativeai`, `anthropic`

### Project Structure

```
scrapper/
├── scrapper/                    # Source code
│   ├── __init__.py             # Package exports
│   ├── web_scraper.py          # Main WebScraper class
│   ├── sources/                # Content source plugins
│   │   ├── __init__.py        # SourceRegistry
│   │   ├── base.py            # ContentSource base class
│   │   ├── wikipedia.py       # Wikipedia source
│   │   └── archive_org.py     # Archive.org source
│   └── models/                 # Data models
│       ├── __init__.py
│       └── article.py          # Pydantic models
├── tests/                      # Tests mirror source structure
│   └── scrapper/
│       ├── test_web_scraper.py
│       ├── test_integration.py
│       └── sources/
│           └── test_sources.py
├── requirements.txt            # All dependencies
├── run_tests.sh               # Test runner script
└── README.md                  # This file
```

## Testing

### Quick Test Run

```bash
cd scrapper

# Run tests (assumes dependencies already installed)
./run_tests.sh

# Or run specific test types
./run_tests.sh -m unit              # Unit tests only
./run_tests.sh -m integration       # Integration tests only
```

### Manual Test Commands

```bash
# Install dependencies (one time)
pip install -r requirements.txt

# All tests
python -m pytest

# Unit tests only (fast, no external API calls)
python -m pytest -m unit

# Integration tests (makes real API calls)
python -m pytest -m integration

# Specific test file
python -m pytest tests/scrapper/test_web_scraper.py -v

# With coverage
python -m pytest --cov=scrapper --cov-report=html
```

### Test Organization

Tests are organized to mirror the source code structure:
- `tests/scrapper/test_web_scraper.py` → tests for `scrapper/web_scraper.py`
- `tests/scrapper/sources/test_sources.py` → tests for `scrapper/sources/`
- `tests/scrapper/test_integration.py` → end-to-end integration tests

## API Reference

### WebScraper

Main scraper class with simple API:

```python
scraper = WebScraper()

# Main method - search and scrape in one call
contents = await scraper.search_and_scrape(
    topic="Mauryan Empire",
    max_pages_per_source=1,      # Pages per source (default: 1)
    sources=None,                 # List of sources or None for all
    respect_robots=False          # Check robots.txt (default: False)
)

# List available sources
sources = scraper.list_sources()  # ['wikipedia', 'archive_org']
```

### ScrapedContent Model

Each scraped page returns a `ScrapedContent` object:

```python
{
    'source_url': str,           # URL of the scraped page
    'title': str,                # Page title
    'raw_text': str,             # LLM-ready markdown content
    'images': List[dict],        # List of images with URLs and metadata
    'metadata': dict,            # Source-specific metadata
    'scraped_at': datetime       # When content was scraped
}
```

## Available Sources

- **wikipedia**: Wikipedia articles (API search + Crawl4AI scraping)
- **archive_org**: Internet Archive content (API search + Crawl4AI scraping)

## Adding New Sources

### Step 1: Create Source Class

Create `scrapper/sources/newsource.py`:

```python
from typing import List, Dict
from .base import ContentSource

class NewSource(ContentSource):
    name = "newsource"  # Unique identifier
    
    def search_topic(self, topic: str, max_results: int = 5) -> List[Dict[str, str]]:
        """
        Search for topic and return results.
        
        Must return list of dicts with: 'title', 'url', 'summary'
        """
        # Use an API or construct URLs
        return [{
            'title': 'Article Title',
            'url': 'https://example.com/article',
            'summary': 'Article summary',
        }]
```

### Step 2: Register Source

Add to `scrapper/sources/__init__.py`:

```python
from .newsource import NewSource

registry.register(NewSource())
```

### Step 3: Use It

```python
scraper = WebScraper()
contents = await scraper.search_and_scrape("topic", sources=["newsource"])
```

The base class handles all scraping automatically using Crawl4AI. You just implement the search logic.

## Architecture

### Class Hierarchy

```
ContentSource (ABC)                    # Base class for all sources
├── search_topic()                     # Abstract: Search and return results
└── extract()                          # Default: Search + scrape with Crawl4AI

WikipediaSource(ContentSource)         # Wikipedia implementation
└── search_topic()                     # Uses Wikipedia API

ArchiveOrgSource(ContentSource)        # Archive.org implementation
└── search_topic()                     # Uses internetarchive library

SourceRegistry                         # Manages source plugins
├── register()                         # Add new source
├── get_source()                       # Get source by name
└── list_sources()                     # List all sources

WebScraper                             # Main scraper class
├── search_and_scrape()                # High-level: search + scrape
├── scrape_all()                       # Scrape from multiple sources
└── list_sources()                     # List available sources
```

## Dependencies

All dependencies are in `requirements.txt`:

**Core dependencies:**
- `crawl4ai>=0.4.0` - Web scraping with LLM optimization
- `wikipedia>=1.4.0` - Wikipedia API wrapper
- `internetarchive>=3.0.0` - Internet Archive API
- `pydantic>=2.0.0` - Data validation

**Test dependencies:**
- `pytest>=7.0.0` - Testing framework
- `pytest-asyncio>=0.21.0` - Async test support

**LLM providers:**
- `google-generativeai` - Google Gemini (optional)
- `anthropic` - Anthropic Claude (optional)

Install all dependencies:
```bash
pip install -r requirements.txt
```
