"""
Unit tests for ImageSourcer. HTTP calls are stubbed at _get_json/_download (same style as
sources/test_sources.py's canned-payload tests), so these need no live network.
"""

from datetime import date

import pytest

from unittest.mock import MagicMock

from common.models import Article, ArticleImage
from scrapper.image_sourcing import HOSTED_IMAGE_WIDTH, ImageSourcer


class FakeVisionLLM:
    """Records every generate_text_with_image call and returns a canned verdict."""

    def __init__(self, relevant: bool = True):
        self.relevant = relevant
        self.calls = 0

    async def generate_text_with_image(self, prompt, image_bytes, media_type, effort=None):
        self.calls += 1
        return f'{{"relevant": {str(self.relevant).lower()}, "reason": "test"}}'


def make_article(article_id="art_20260101_001", title="Mohenjo-daro"):
    return Article(
        id=article_id, title=title, summary="An ancient Indus Valley city.", content="...",
        publication_date=date(2026, 1, 1), reading_time_minutes=10,
    )


WIKIPEDIA_PAGE_RESPONSE = {
    "query": {"pages": {"1": {
        "pageid": 1, "title": "Mohenjo-daro", "pageimage": "Mohenjodaro_Sindh.jpeg",
        "images": [
            {"ns": 6, "title": "File:Mohenjodaro_Sindh.jpeg"},
            {"ns": 6, "title": "File:Commons-logo.svg"},
            {"ns": 6, "title": "File:Great_Bath.jpg"},
        ],
    }}}
}

GOOD_JPEG_INFO = {
    "url": "https://upload.wikimedia.org/wikipedia/commons/a/Mohenjodaro_Sindh.jpeg",
    "width": 1200, "height": 800, "mime": "image/jpeg",
    "extmetadata": {
        "LicenseShortName": {"value": "CC BY-SA 4.0"},
        "Artist": {"value": '<a href="https://example.com">Jane Doe</a>'},
        "ImageDescription": {"value": "The ruins of Mohenjo-daro"},
    },
}

SECOND_GOOD_JPEG_INFO = {
    **GOOD_JPEG_INFO,
    "url": "https://upload.wikimedia.org/wikipedia/commons/b/Great_Bath.jpg",
    "extmetadata": {
        "LicenseShortName": {"value": "Public domain"},
        "Artist": {"value": "Unknown"},
        "ImageDescription": {"value": ""},
    },
}


def imageinfo_response(entries: dict[str, dict]) -> dict:
    """entries: {filename_title: imageinfo_dict}"""
    return {"query": {"pages": {
        str(i): {"title": title, "imageinfo": [info]} for i, (title, info) in enumerate(entries.items())
    }}}


def stub_get_json(responses_by_action: dict):
    """responses_by_action: {(action_signature): response}. Matches on whether params look like
    the pageimages call, the imageinfo call, or the Commons search call."""

    async def _get_json(self, url, params):
        if "generator" in params:
            return responses_by_action.get("search", {"query": {"pages": {}}})
        if params.get("prop") == "pageimages|images":
            return responses_by_action.get("page", {"query": {"pages": {}}})
        return responses_by_action.get("imageinfo", {"query": {"pages": {}}})
    return _get_json


class TestImageSourcer:
    def test_init(self):
        sourcer = ImageSourcer(llm_provider=FakeVisionLLM())
        assert sourcer is not None

    async def test_sources_hero_first_then_inline_from_wikipedias_own_images(self, monkeypatch):
        monkeypatch.setattr(ImageSourcer, "_get_json", stub_get_json({
            "page": WIKIPEDIA_PAGE_RESPONSE,
            "imageinfo": imageinfo_response({
                "File:Mohenjodaro_Sindh.jpeg": GOOD_JPEG_INFO,
                "File:Great_Bath.jpg": SECOND_GOOD_JPEG_INFO,
            }),
        }))
        monkeypatch.setattr(ImageSourcer, "_download", lambda self, url: _bytes())
        monkeypatch.setattr(ImageSourcer, "_host", fake_host)

        sourcer = ImageSourcer(llm_provider=FakeVisionLLM())
        images = await sourcer.source_images(make_article(), topic="Mohenjo-daro")

        assert [i.credit for i in images] == ["Jane Doe via Wikimedia Commons", "Unknown via Wikimedia Commons"]
        assert images[0].caption == "The ruins of Mohenjo-daro"
        assert images[0].license == "CC BY-SA 4.0"

    async def test_junk_filenames_are_filtered_out(self, monkeypatch):
        """Commons-logo.svg must never reach imageinfo/quality-gate at all."""
        seen_titles = []

        async def recording_get_json(self, url, params):
            if params.get("prop") == "pageimages|images":
                return WIKIPEDIA_PAGE_RESPONSE
            seen_titles.extend(params.get("titles", "").split("|"))
            return imageinfo_response({
                "File:Mohenjodaro_Sindh.jpeg": GOOD_JPEG_INFO,
                "File:Great_Bath.jpg": SECOND_GOOD_JPEG_INFO,
            })

        monkeypatch.setattr(ImageSourcer, "_get_json", recording_get_json)
        monkeypatch.setattr(ImageSourcer, "_download", lambda self, url: _bytes())
        monkeypatch.setattr(ImageSourcer, "_host", fake_host)

        sourcer = ImageSourcer(llm_provider=FakeVisionLLM())
        await sourcer.source_images(make_article(), topic="Mohenjo-daro")

        assert "File:Commons-logo.svg" not in seen_titles

    async def test_rejects_non_commercial_license(self, monkeypatch):
        nc_info = {**GOOD_JPEG_INFO, "extmetadata": {
            "LicenseShortName": {"value": "CC BY-NC 4.0"}, "Artist": {"value": "X"}, "ImageDescription": {"value": ""},
        }}
        monkeypatch.setattr(ImageSourcer, "_get_json", stub_get_json({
            "page": WIKIPEDIA_PAGE_RESPONSE,
            "imageinfo": imageinfo_response({"File:Mohenjodaro_Sindh.jpeg": nc_info}),
        }))
        monkeypatch.setattr(ImageSourcer, "_download", lambda self, url: _bytes())
        monkeypatch.setattr(ImageSourcer, "_host", fake_host)

        sourcer = ImageSourcer(llm_provider=FakeVisionLLM())
        images = await sourcer.source_images(make_article(), topic="Mohenjo-daro")

        assert images == []

    async def test_rejects_images_below_the_minimum_width(self, monkeypatch):
        small_info = {**GOOD_JPEG_INFO, "width": 100}
        monkeypatch.setattr(ImageSourcer, "_get_json", stub_get_json({
            "page": WIKIPEDIA_PAGE_RESPONSE,
            "imageinfo": imageinfo_response({"File:Mohenjodaro_Sindh.jpeg": small_info}),
        }))
        monkeypatch.setattr(ImageSourcer, "_download", lambda self, url: _bytes())
        monkeypatch.setattr(ImageSourcer, "_host", fake_host)

        sourcer = ImageSourcer(llm_provider=FakeVisionLLM())
        images = await sourcer.source_images(make_article(), topic="Mohenjo-daro")

        assert images == []

    async def test_rejects_svg(self, monkeypatch):
        svg_info = {**GOOD_JPEG_INFO, "mime": "image/svg+xml"}
        monkeypatch.setattr(ImageSourcer, "_get_json", stub_get_json({
            "page": WIKIPEDIA_PAGE_RESPONSE,
            "imageinfo": imageinfo_response({"File:Mohenjodaro_Sindh.jpeg": svg_info}),
        }))
        monkeypatch.setattr(ImageSourcer, "_download", lambda self, url: _bytes())
        monkeypatch.setattr(ImageSourcer, "_host", fake_host)

        sourcer = ImageSourcer(llm_provider=FakeVisionLLM())
        images = await sourcer.source_images(make_article(), topic="Mohenjo-daro")

        assert images == []

    async def test_falls_back_to_commons_search_when_wikipedia_has_too_few_images(self, monkeypatch):
        empty_page = {"query": {"pages": {"1": {"pageid": 1, "title": "Obscure Topic"}}}}
        commons_result = imageinfo_response({"File:Some_Relic.jpg": GOOD_JPEG_INFO})

        monkeypatch.setattr(ImageSourcer, "_get_json", stub_get_json({
            "page": empty_page, "search": commons_result,
        }))
        monkeypatch.setattr(ImageSourcer, "_download", lambda self, url: _bytes())
        monkeypatch.setattr(ImageSourcer, "_host", fake_host)

        fake_llm = FakeVisionLLM(relevant=True)
        sourcer = ImageSourcer(llm_provider=fake_llm)
        images = await sourcer.source_images(make_article(), topic="Obscure Topic")

        assert len(images) == 1
        assert fake_llm.calls == 1  # only Commons-sourced candidates get the vision check

    async def test_commons_fallback_candidate_rejected_by_vision_check_is_dropped(self, monkeypatch):
        empty_page = {"query": {"pages": {"1": {"pageid": 1, "title": "Obscure Topic"}}}}
        commons_result = imageinfo_response({"File:Unrelated.jpg": GOOD_JPEG_INFO})

        monkeypatch.setattr(ImageSourcer, "_get_json", stub_get_json({
            "page": empty_page, "search": commons_result,
        }))
        monkeypatch.setattr(ImageSourcer, "_download", lambda self, url: _bytes())
        monkeypatch.setattr(ImageSourcer, "_host", fake_host)

        sourcer = ImageSourcer(llm_provider=FakeVisionLLM(relevant=False))
        images = await sourcer.source_images(make_article(), topic="Obscure Topic")

        assert images == []

    async def test_wikipedia_sourced_candidates_skip_the_vision_check(self, monkeypatch):
        monkeypatch.setattr(ImageSourcer, "_get_json", stub_get_json({
            "page": WIKIPEDIA_PAGE_RESPONSE,
            "imageinfo": imageinfo_response({"File:Mohenjodaro_Sindh.jpeg": GOOD_JPEG_INFO}),
        }))
        monkeypatch.setattr(ImageSourcer, "_download", lambda self, url: _bytes())
        monkeypatch.setattr(ImageSourcer, "_host", fake_host)

        fake_llm = FakeVisionLLM()
        sourcer = ImageSourcer(llm_provider=fake_llm)
        await sourcer.source_images(make_article(), topic="Mohenjo-daro")

        assert fake_llm.calls == 0

    async def test_exclude_keeps_a_rejected_filename_out_even_when_it_would_be_top_pick(self, monkeypatch):
        monkeypatch.setattr(ImageSourcer, "_get_json", stub_get_json({
            "page": WIKIPEDIA_PAGE_RESPONSE,
            "imageinfo": imageinfo_response({
                "File:Mohenjodaro_Sindh.jpeg": GOOD_JPEG_INFO,
                "File:Great_Bath.jpg": SECOND_GOOD_JPEG_INFO,
            }),
        }))
        monkeypatch.setattr(ImageSourcer, "_download", lambda self, url: _bytes())
        monkeypatch.setattr(ImageSourcer, "_host", fake_host)

        sourcer = ImageSourcer(llm_provider=FakeVisionLLM())
        images = await sourcer.source_images(
            make_article(), topic="Mohenjo-daro", exclude={"File:Mohenjodaro_Sindh.jpeg"}
        )

        assert [i.alt_text for i in images] == ["File:Great_Bath.jpg"]

    async def test_returns_empty_list_rather_than_raising_when_nothing_is_found(self, monkeypatch):
        monkeypatch.setattr(ImageSourcer, "_get_json", stub_get_json({
            "page": {"query": {"pages": {"1": {"pageid": 1, "title": "Nonexistent"}}}},
            "search": {"query": {"pages": {}}},
        }))

        sourcer = ImageSourcer(llm_provider=FakeVisionLLM())
        images = await sourcer.source_images(make_article(), topic="Nonexistent")

        assert images == []

    @pytest.mark.parametrize("license_name,allowed", [
        ("CC BY-SA 4.0", True), ("CC BY 4.0", True), ("CC0", True), ("Public domain", True),
        ("CC BY-NC 4.0", False), ("CC BY-ND 4.0", False), ("", False), ("All rights reserved", False),
    ])
    def test_license_allowlist(self, license_name, allowed):
        assert ImageSourcer._license_allowed(license_name) is allowed


async def _bytes() -> bytes:
    return b"fake-image-bytes"


async def fake_host(self, article_id, index, filename, info, image_bytes):
    from common.models import ArticleImage
    extmetadata = info.get("extmetadata", {})
    from scrapper.image_sourcing import _clean_html
    artist = _clean_html(extmetadata.get("Artist", {}).get("value", "")) or "Unknown"
    return ArticleImage(
        url=f"https://storage.example/{article_id}/{index}",
        alt_text=filename,
        caption=_clean_html(extmetadata.get("ImageDescription", {}).get("value", "")) or None,
        credit=f"{artist} via Wikimedia Commons",
        source_url=f"https://commons.wikimedia.org/wiki/{filename}",
        license=extmetadata.get("LicenseShortName", {}).get("value", "Public domain"),
        width=info["width"],
        height=info["height"],
    )


class TestScaledImages:
    """Wikimedia scales larger originals to HOSTED_IMAGE_WIDTH; we host that, under a name made from its content."""

    async def test_asks_wikimedia_for_a_scaled_version_and_downloads_it(self, monkeypatch):
        seen_params, downloaded = [], []
        scaled = {**GOOD_JPEG_INFO, "width": 4000, "height": 3000,
                  "thumburl": "https://upload.wikimedia.org/thumb/1600px-Mohenjodaro_Sindh.jpeg",
                  "thumbwidth": 1600, "thumbheight": 1200}
        stub = stub_get_json({"page": WIKIPEDIA_PAGE_RESPONSE,
                              "imageinfo": imageinfo_response({"File:Mohenjodaro_Sindh.jpeg": scaled})})

        async def recording_get_json(self, url, params):
            seen_params.append(params)
            return await stub(self, url, params)

        async def recording_download(self, url):
            downloaded.append(url)
            return b"scaled-bytes"

        monkeypatch.setattr(ImageSourcer, "_get_json", recording_get_json)
        monkeypatch.setattr(ImageSourcer, "_download", recording_download)
        monkeypatch.setattr(ImageSourcer, "_host", fake_host)

        await ImageSourcer(llm_provider=FakeVisionLLM()).source_images(make_article(), topic="Mohenjo-daro")

        assert downloaded == ["https://upload.wikimedia.org/thumb/1600px-Mohenjodaro_Sindh.jpeg"]
        imageinfo_calls = [p for p in seen_params if p.get("prop") == "imageinfo"]
        assert imageinfo_calls and all(p["iiurlwidth"] == HOSTED_IMAGE_WIDTH for p in imageinfo_calls)

    async def test_hosts_under_a_content_named_path_with_the_scaled_size(self, monkeypatch):
        uploads = []
        bucket = MagicMock()
        bucket.upload.side_effect = lambda path, data, file_options: uploads.append(path)
        bucket.get_public_url.side_effect = lambda path: f"https://storage.example/{path}"
        admin = MagicMock()
        admin.storage.from_.return_value = bucket
        monkeypatch.setattr("scrapper.image_sourcing.get_supabase", lambda: MagicMock(get_admin_client=lambda: admin))
        monkeypatch.setattr("scrapper.image_sourcing.get_settings", lambda: MagicMock(articles_storage_bucket="articles"))
        info = {**GOOD_JPEG_INFO, "width": 4000, "height": 3000, "thumbwidth": 1600, "thumbheight": 1200}
        sourcer = ImageSourcer(llm_provider=FakeVisionLLM())

        first = await sourcer._host("art_1", 0, "File:A.jpeg", info, b"one")
        second = await sourcer._host("art_1", 0, "File:A.jpeg", info, b"two")

        assert uploads[0].startswith("images/art_1/0-") and uploads[0].endswith(".jpeg")
        assert uploads[0] != uploads[1]  # a replacement never reuses a path a CDN may have cached
        assert (first.width, first.height) == (1600, 1200)
        assert second.url.endswith(uploads[1])

    async def test_rehost_keeps_each_picture_and_its_credits_but_hosts_it_scaled(self, monkeypatch):
        article = make_article()
        article.images = [ArticleImage(
            url="https://storage.example/old.jpeg", alt_text="Ruins", caption="The ruins", credit="Jane via Wikimedia Commons",
            source_url="https://commons.wikimedia.org/wiki/File:Mohenjodaro_Sindh.jpeg", license="CC BY-SA 4.0",
            width=4000, height=3000)]
        scaled = {**GOOD_JPEG_INFO, "width": 4000, "height": 3000,
                  "thumburl": "https://upload.wikimedia.org/thumb/1600px.jpeg", "thumbwidth": 1600, "thumbheight": 1200}
        looked_up = []

        async def imageinfo(self, filenames):
            looked_up.extend(filenames)
            return {"File:Mohenjodaro Sindh.jpeg": scaled}

        async def host(self, article_id, index, filename, info, image_bytes):
            return ArticleImage(url="https://storage.example/new.jpeg", alt_text="x", credit="x", source_url="x",
                                license="x", width=info["thumbwidth"], height=info["thumbheight"])

        monkeypatch.setattr(ImageSourcer, "_imageinfo", imageinfo)
        monkeypatch.setattr(ImageSourcer, "_download", lambda self, url: _bytes())
        monkeypatch.setattr(ImageSourcer, "_host", host)

        [image] = await ImageSourcer(llm_provider=FakeVisionLLM()).rehost(article)

        assert looked_up == ["File:Mohenjodaro_Sindh.jpeg"]
        assert (image.url, image.width, image.height) == ("https://storage.example/new.jpeg", 1600, 1200)
        assert (image.alt_text, image.caption, image.credit, image.license) == (
            "Ruins", "The ruins", "Jane via Wikimedia Commons", "CC BY-SA 4.0")

    async def test_rehost_keeps_an_image_it_cannot_look_up(self, monkeypatch):
        article = make_article()
        original = ArticleImage(url="https://storage.example/old.jpeg", alt_text="a", credit="c",
                                source_url="https://commons.wikimedia.org/wiki/File:Gone.jpg", license="PD",
                                width=900, height=600)
        article.images = [original]

        async def nothing(self, filenames):
            return {}

        monkeypatch.setattr(ImageSourcer, "_imageinfo", nothing)

        assert await ImageSourcer(llm_provider=FakeVisionLLM()).rehost(article) == [original]

    async def test_rehost_leaves_an_image_already_within_the_hosted_width(self, monkeypatch):
        article = make_article()
        small = ArticleImage(url="https://storage.example/old.jpeg", alt_text="a", credit="c",
                             source_url="https://commons.wikimedia.org/wiki/File:Small.jpg", license="PD",
                             width=1200, height=800)
        article.images = [small]

        async def imageinfo(self, filenames):
            return {"File:Small.jpg": {**GOOD_JPEG_INFO, "width": 1200, "height": 800}}

        async def must_not_host(*args):
            raise AssertionError("re-hosted an image that was already small")

        monkeypatch.setattr(ImageSourcer, "_imageinfo", imageinfo)
        monkeypatch.setattr(ImageSourcer, "_host", must_not_host)

        assert await ImageSourcer(llm_provider=FakeVisionLLM()).rehost(article) == [small]
