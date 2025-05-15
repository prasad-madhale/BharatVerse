import os, json
import asyncio
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

from crawl4ai import (
    AsyncWebCrawler,
    LLMExtractionStrategy,
    BrowserConfig,
    LLMConfig,
    CrawlerRunConfig,
    CacheMode,
)

from model.article import Article

URL = "https://en.wikipedia.org/wiki/Neha_Mehta"
LLM_API_KEY = os.getenv("ANTHROPIC_CLAUDE_API_KEY")
LLM_MODEL = "anthropic/claude-3-5-sonnet-20240620"


async def crawl_article():
    print(LLM_API_KEY)
    browser_config = get_browser_config()
    crawl_config = CrawlerRunConfig(
        extraction_strategy=get_llm_strategy(), cache_mode=CacheMode.ENABLED
    )

    print("Starting the web crawler...")
    async with AsyncWebCrawler(config=browser_config) as crawler:
        result = await crawler.arun(url=URL, config=crawl_config)
        print("Web crawler finished.")

        if result.success:
            # The extracted content is presumably JSON
            data = json.loads(result.extracted_content)
            print("Extracted items:", data)
        else:
            print("Error:", result.error_message)
    return result


def get_browser_config() -> BrowserConfig:
    return BrowserConfig(browser_type="chromium", headless=False, verbose=True)


def get_llm_strategy() -> LLMExtractionStrategy:
    """
    Returns configuration for the LLM extraction strategy.
    """
    return LLMExtractionStrategy(
        llm_config=LLMConfig(provider=LLM_MODEL, api_token=LLM_API_KEY),
        schema=Article.model_json_schema(),
        extraction_type="schema",
        instruction=get_instruction(),
        chunk_token_threshold=1200,
        overlap_rate=0.1,
        apply_chunking=True,
        input_format="markdown",
        verbose=True,
    )


def get_instruction() -> str:
    """
    Returns the instruction for the LLM extraction strategy.
    """
    return (
        "Extract fields like title, table_of_contents, url, date, author, tags, references from the text."
        "Where references are the sources cited in the article."
        "url is the link to the article."
        "date is the date of publication."
        "author is the name of the author."
        "tags are the keywords associated with the article."
        "table_of_contents is a dictionary with the sub-section title as keys and their content as values."
        "title is the title of the article."
    )


if __name__ == "__main__":
    asyncio.run(crawl_article())
