import os
import asyncio

from crawl4ai import AsyncWebCrawler, LLMExtractionStrategy, BrowserConfig, LLMConfig

from model.article import Article

URL = "https://en.wikipedia.org/wiki/Shivaji"
LLM_API_KEY = os.getenv("GROQ_API_KEY")
LLM_MODEL = "deepseek/deepseek-chat"


async def crawl_article():
    browser_config = get_browser_config()

    print("Starting the web crawler...")
    async with AsyncWebCrawler(config=browser_config) as crawler:
        result = await crawler.arun(
            url=URL,
            extraction_strategy=get_llm_strategy(),
        )
        print("Web crawler finished.")
    print("Result:", result)
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
        instruction="Extract a list of items from the text with 'name' and 'price' fields.",
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
