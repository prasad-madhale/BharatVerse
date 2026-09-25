"""
Sources images for a generated Article.

Every topic this pipeline generates is chosen to match a real Wikipedia title
(topic_generator.py), so the primary source is that page's own images -- a human editor already
selected these for relevance. A Wikimedia Commons keyword search fills in when the page has too
few usable images (stubs); because that path is a keyword match rather than a curated choice, its
candidates also get an LLM vision relevance check before being used. Every image is downloaded and
re-hosted in our own Supabase Storage (see docs/design.md), never hotlinked, and only Public
Domain/CC0/CC-BY/CC-BY-SA licensed images are used, with full attribution carried through to
ArticleImage.

See docs/roadmap.md and requirements.md 5.5.
"""

import asyncio
import logging
import re

import json_repair
import requests

from backend.config import get_settings
from backend.database import get_supabase
from common.config import get_llm_settings
from common.llm_provider import LLMProvider, get_llm_provider
from common.models import Article, ArticleImage

logger = logging.getLogger(__name__)

WIKIPEDIA_API = "https://en.wikipedia.org/w/api.php"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "BharatVerse/1.0 (https://github.com/prasad-madhale/BharatVerse; content pipeline)"
HTTP_TIMEOUT_SECONDS = 15
MIN_COMMONS_CANDIDATES_BEFORE_FALLBACK = 2
COMMONS_SEARCH_LIMIT = 8
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}

# A stable set of Wikipedia/Commons UI-chrome filenames (icons, logos, edit pencils, flags used as
# tiny inline markers) that turn up in a page's embedded-images list alongside real content photos.
JUNK_FILENAME_RE = re.compile(
    r"(commons-logo|wiki(pedia|source|media|books|quote)?[-_]?logo|edit[-_]?icon|ambox|"
    r"question_book|wiki_letter|folder|disambig|padlock|nuvola|crystal_clear|sound[-_]?icon|"
    r"loudspeaker|[a-z]+_pog|symbol_|text_document|icon[-_.]|_icon\.|commonscat|wikidata[-_]logo)",
    re.IGNORECASE,
)

RELEVANCE_PROMPT_TEMPLATE = """You are checking whether an image is a reasonable illustration for a
history article, before it gets published.

Article title: {title}
Article summary: {summary}

Does this image plausibly depict, or directly relate to, the subject above (the place, person,
object, event, or era)? A reasonable establishing or contextual image counts; an image that is
clearly about something unrelated does not.

Respond with ONLY a JSON object, no markdown fences, matching exactly this shape:
{{"relevant": true or false, "reason": "one short sentence"}}"""


class ImageSourcer:
    """Finds, quality-checks, and re-hosts images for an Article."""

    def __init__(self, llm_provider: LLMProvider | None = None):
        self.llm_provider = llm_provider or get_llm_provider()
        self.settings = get_llm_settings()

    async def source_images(
        self, article: Article, topic: str, exclude: set[str] = frozenset()
    ) -> list[ArticleImage]:
        """
        Returns up to settings.target_image_count ArticleImages for the article, or an empty
        list if nothing usable was found -- callers should treat that as "publish with no
        images", not an error.

        exclude: Commons file titles (e.g. "File:Foo.jpg", as recovered from a rejected
        ArticleImage.source_url's last path segment) to leave out of the candidate set --
        used by a critic-triggered retry so it can't just re-select an image already rejected
        for failing the cohesion check.
        """
        candidates = await self._wikipedia_candidates(topic)
        needs_check = {filename: False for filename in candidates}

        if len(candidates) < MIN_COMMONS_CANDIDATES_BEFORE_FALLBACK:
            fallback = await self._commons_search_candidates(topic)
            for filename, info in fallback.items():
                if filename not in candidates:
                    candidates[filename] = info
                    needs_check[filename] = True

        if exclude:
            excluded = {name.replace(" ", "_") for name in exclude}
            candidates = {
                filename: info for filename, info in candidates.items()
                if filename.replace(" ", "_") not in excluded
            }

        images: list[ArticleImage] = []
        for filename, info in candidates.items():
            if len(images) >= self.settings.target_image_count:
                break
            if not self._passes_quality_gate(filename, info):
                continue
            try:
                image_bytes = await self._download(info["url"])
            except Exception:
                logger.warning(f"Failed to download {filename}, skipping", exc_info=True)
                continue
            if needs_check[filename] and not await self._passes_relevance_check(image_bytes, info, article):
                continue
            image = await self._host(article.id, len(images), filename, info, image_bytes)
            images.append(image)

        logger.info(f"Sourced {len(images)} image(s) for '{topic}'")
        return images

    async def _wikipedia_candidates(self, topic: str) -> dict[str, dict]:
        """The topic's Wikipedia page's own lead image plus embedded images, junk-filtered,
        each with their imageinfo (license, size, url). Order matters: the lead image (if any)
        is first, so it becomes the featured image."""
        page = await self._get_json(WIKIPEDIA_API, {
            "action": "query", "titles": topic, "prop": "pageimages|images",
            "pithumbsize": 1200, "imlimit": 50, "format": "json",
        })
        pages = page.get("query", {}).get("pages", {})
        if not pages:
            return {}
        page_data = next(iter(pages.values()))

        filenames: list[str] = []
        lead = page_data.get("pageimage")
        if lead:
            filenames.append(f"File:{lead}")
        for image in page_data.get("images", []):
            title = image.get("title", "")
            name = title.removeprefix("File:")
            if title not in filenames and not JUNK_FILENAME_RE.search(name):
                filenames.append(title)

        if not filenames:
            return {}
        # MediaWiki's batched response doesn't preserve request order (it's keyed by pageid),
        # so re-order by our own filenames list -- the lead image must stay first to become
        # the featured image.
        info_by_title = await self._imageinfo(filenames)
        return {title: info_by_title[title] for title in filenames if title in info_by_title}

    async def _commons_search_candidates(self, topic: str) -> dict[str, dict]:
        """A Commons keyword search, for when the Wikipedia page itself has too few images."""
        response = await self._get_json(COMMONS_API, {
            "action": "query", "generator": "search", "gsrsearch": topic,
            "gsrnamespace": 6, "gsrlimit": COMMONS_SEARCH_LIMIT,
            "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "format": "json",
        })
        pages = response.get("query", {}).get("pages", {})
        result = {}
        for page_data in pages.values():
            title = page_data.get("title", "")
            name = title.removeprefix("File:")
            infos = page_data.get("imageinfo")
            if infos and not JUNK_FILENAME_RE.search(name):
                result[title] = infos[0]
        return result

    async def _imageinfo(self, filenames: list[str]) -> dict[str, dict]:
        """Batched license/size/url lookup, up to 50 titles per MediaWiki call."""
        result: dict[str, dict] = {}
        for batch_start in range(0, len(filenames), 50):
            batch = filenames[batch_start:batch_start + 50]
            response = await self._get_json(COMMONS_API, {
                "action": "query", "titles": "|".join(batch),
                "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "format": "json",
            })
            for page_data in response.get("query", {}).get("pages", {}).values():
                infos = page_data.get("imageinfo")
                if infos:
                    result[page_data["title"]] = infos[0]
        return result

    def _passes_quality_gate(self, filename: str, info: dict) -> bool:
        if info.get("mime") not in ALLOWED_MIME_TYPES:
            return False
        if info.get("width", 0) < self.settings.min_image_width:
            return False
        license_short = info.get("extmetadata", {}).get("LicenseShortName", {}).get("value", "")
        if not self._license_allowed(license_short):
            logger.debug(f"Rejected {filename}: license '{license_short}' not reusable")
            return False
        return True

    @staticmethod
    def _license_allowed(license_short_name: str) -> bool:
        name = license_short_name.lower().strip()
        if not name:
            return False
        if re.search(r"\bnc\b|\bnd\b", name):
            return False
        return bool(re.search(r"\bcc0\b|\bcc[\s-]?by(-sa)?\b|public domain|\bpd\b", name))

    async def _passes_relevance_check(self, image_bytes: bytes, info: dict, article: Article) -> bool:
        try:
            prompt = RELEVANCE_PROMPT_TEMPLATE.format(title=article.title, summary=article.summary)
            raw = await self.llm_provider.generate_text_with_image(
                prompt, image_bytes, info["mime"], effort="medium"
            )
            parsed = json_repair.loads(_strip_code_fence(raw))
            return bool(isinstance(parsed, dict) and parsed.get("relevant"))
        except Exception:
            logger.warning("Image relevance check failed; treating as not relevant", exc_info=True)
            return False

    async def _host(
        self, article_id: str, index: int, filename: str, info: dict, image_bytes: bytes
    ) -> ArticleImage:
        extension = info["mime"].split("/")[-1]
        storage_path = f"images/{article_id}/{index}.{extension}"
        client = get_supabase().get_admin_client()
        bucket = get_settings().articles_storage_bucket
        await asyncio.to_thread(
            client.storage.from_(bucket).upload,
            storage_path, image_bytes,
            file_options={"content-type": info["mime"], "upsert": "true"},
        )
        hosted_url = client.storage.from_(bucket).get_public_url(storage_path)

        extmetadata = info.get("extmetadata", {})
        artist = _clean_html(extmetadata.get("Artist", {}).get("value", "")) or "Unknown"
        name = filename.removeprefix("File:")
        return ArticleImage(
            url=hosted_url,
            alt_text=name.rsplit(".", 1)[0].replace("_", " "),
            caption=_clean_html(extmetadata.get("ImageDescription", {}).get("value", "")) or None,
            credit=f"{artist} via Wikimedia Commons",
            source_url=f"https://commons.wikimedia.org/wiki/{filename.replace(' ', '_')}",
            license=extmetadata.get("LicenseShortName", {}).get("value", "Public domain"),
            width=info["width"],
            height=info["height"],
        )

    async def _get_json(self, url: str, params: dict) -> dict:
        def _fetch():
            response = requests.get(url, params=params, headers={"User-Agent": USER_AGENT}, timeout=HTTP_TIMEOUT_SECONDS)
            response.raise_for_status()
            return response.json()
        return await asyncio.to_thread(_fetch)

    async def _download(self, url: str) -> bytes:
        def _fetch():
            response = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=HTTP_TIMEOUT_SECONDS)
            response.raise_for_status()
            return response.content
        return await asyncio.to_thread(_fetch)


def _strip_code_fence(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[len("json"):]
    return text.strip()


def _clean_html(value: str) -> str:
    """extmetadata text fields (Artist, ImageDescription) commonly contain HTML like
    '<a href="...">Name</a>' -- strip tags for a plain-text credit/caption."""
    return re.sub(r"<[^>]+>", "", value).strip()
