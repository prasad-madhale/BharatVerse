"""
Unit tests for the daily pipeline orchestrator (scrapper.scheduler).

All collaborators (ArticleService, TopicGenerator, WebScraper,
ArticleGenerator, ContentValidator) and the backoff sleep are mocked -- this
tests the orchestration logic only, not any real scraping/LLM/Supabase
behavior (those are covered by each collaborator's own tests).
"""

import logging
from datetime import date, datetime, timezone
from types import SimpleNamespace
from unittest.mock import ANY, AsyncMock, MagicMock, patch

import pytest

from common.models import Article, ArticleImage, Citation, Section
from scrapper import scheduler
from scrapper.article_critic import CriticIssue, CriticReview
from scrapper.article_generator import ArticleGenerationError


def _make_article(article_id="art_20260705_001", title="Some Article"):
    article = MagicMock()
    article.id = article_id
    article.title = title
    return article


def _real_article(words=1800, sections=3, citations=2):
    return Article(
        id="art_20260705_001",
        title="From Conquest to Compassion",
        summary="A summary.",
        content=" ".join(["word"] * words),
        sections=[Section(heading=f"S{n}", content="...", order=n) for n in range(1, sections + 1)],
        citations=[
            Citation(text="Ashoka", source_url="https://en.wikipedia.org/wiki/Ashoka", source_name="wikipedia",
                     accessed_date=datetime(2026, 7, 5, tzinfo=timezone.utc))
            for _ in range(citations)
        ],
        publication_date=date(2026, 7, 5),
        reading_time_minutes=13,
    )


def _approved(summary="ok"):
    return CriticReview(approved=True, summary=summary, issues=[])


def _rejected(summary="needs work"):
    return CriticReview(approved=False, summary=summary, issues=[
        CriticIssue(category="grounding", severity="major", location="Origins",
                    detail="unsupported claim", suggestion="remove it"),
    ])


def _image(url="https://s/0.jpg", source_url="https://commons.wikimedia.org/wiki/File:X.jpg"):
    return ArticleImage(
        url=url, alt_text="a", credit="Someone via Wikimedia Commons",
        source_url=source_url, license="CC BY-SA 4.0", width=1200, height=800,
    )


def _cohesion_issue(location="featured image", detail="Unrelated to the article"):
    return CriticIssue(
        category="image_cohesion", severity="major", location=location,
        detail=detail, suggestion="Source a different image",
    )


@pytest.fixture
def pipeline():
    """The pipeline with every collaborator mocked: one topic, scraped content, and articles that
    validate and are approved by the critic on the first round."""
    with patch("scrapper.scheduler.ArticleService") as service_cls, \
            patch("scrapper.scheduler.TopicGenerator") as topics_cls, \
            patch("scrapper.scheduler.WebScraper") as scraper_cls, \
            patch("scrapper.scheduler.ArticleGenerator") as generator_cls, \
            patch("scrapper.scheduler.ContentValidator") as validator_cls, \
            patch("scrapper.scheduler.ArticleCritic") as critic_cls, \
            patch("scrapper.scheduler.ImageSourcer") as image_sourcer_cls, \
            patch("scrapper.scheduler.sleep", new_callable=AsyncMock) as sleep:
        service = service_cls.return_value
        service.list_recent_titles = AsyncMock(return_value=[])
        service.save_article = AsyncMock()
        topics = topics_cls.return_value
        topics.generate_topics = AsyncMock(return_value=["Topic"])
        scraper = scraper_cls.return_value
        scraper.search_and_scrape = AsyncMock(return_value=["scraped content"])
        generator = generator_cls.return_value
        generator.generate_article = AsyncMock(return_value=_make_article())
        generator.revise_article = AsyncMock(return_value=_make_article("art_revised"))
        validator = validator_cls.return_value
        validator.validate.return_value = (True, [])
        critic = critic_cls.return_value
        critic.review = AsyncMock(return_value=_approved())
        critic.review_image_cohesion = AsyncMock(return_value=[])
        image_sourcer = image_sourcer_cls.return_value
        image_sourcer.source_images = AsyncMock(return_value=[])
        yield SimpleNamespace(service=service, topics=topics, scraper=scraper, generator=generator,
                              validator=validator, critic=critic, image_sourcer=image_sourcer, sleep=sleep)


class TestRunDailyPipeline:
    async def test_happy_path_generates_and_publishes_one_article(self, pipeline):
        pipeline.service.list_recent_titles.return_value = ["Old Topic"]
        pipeline.topics.generate_topics.return_value = ["New Topic"]
        article = _make_article()
        pipeline.generator.generate_article.return_value = article

        published = await scheduler.run_daily_pipeline(count=1)

        pipeline.topics.generate_topics.assert_awaited_once_with(count=1, exclude_titles=["Old Topic"])
        pipeline.scraper.search_and_scrape.assert_awaited_once_with("New Topic", sources=scheduler.SOURCES)
        pipeline.generator.generate_article.assert_awaited_once_with(["scraped content"], topic="New Topic", sequence=1)
        pipeline.service.save_article.assert_awaited_once_with(article)
        assert published == 1

    async def test_multiple_topics_get_sequential_sequence_numbers(self, pipeline):
        pipeline.topics.generate_topics.return_value = ["Topic A", "Topic B"]
        pipeline.generator.generate_article.side_effect = [_make_article("art_1"), _make_article("art_2")]

        published = await scheduler.run_daily_pipeline(count=2)

        calls = pipeline.generator.generate_article.await_args_list
        assert [call.kwargs["sequence"] for call in calls] == [1, 2]
        assert pipeline.service.save_article.await_count == 2
        assert published == 2

    async def test_skips_topic_with_no_scraped_content(self, pipeline):
        pipeline.scraper.search_and_scrape.return_value = []

        published = await scheduler.run_daily_pipeline(count=1)

        pipeline.generator.generate_article.assert_not_awaited()
        pipeline.service.save_article.assert_not_awaited()
        assert published == 0

    async def test_retries_at_once_on_validation_failure_then_publishes(self, pipeline):
        second = _make_article("art_good")
        pipeline.generator.generate_article.side_effect = [_make_article("art_bad"), second]
        # (False, ...) for the failed attempt's structural check, then (True, []) twice for the
        # second attempt's: once before the critic loop, once again at the top of its round 1
        # (run_critic_loop's own structural check, so it can catch an already-invalid starting
        # article even when the caller didn't just validate it -- see reprocess_articles.py).
        pipeline.validator.validate.side_effect = [(False, ["too short"]), (True, []), (True, [])]

        published = await scheduler.run_daily_pipeline(count=1)

        assert pipeline.generator.generate_article.await_count == 2
        pipeline.service.save_article.assert_awaited_once_with(second)
        pipeline.sleep.assert_not_awaited()  # the draft arrived, so the next one need not wait
        assert published == 1

    async def test_skips_topic_when_every_attempt_is_invalid(self, pipeline):
        pipeline.generator.generate_article.side_effect = [_make_article(f"art_bad{n}") for n in range(3)]
        pipeline.validator.validate.return_value = (False, ["too short"])

        published = await scheduler.run_daily_pipeline(count=1)

        assert pipeline.generator.generate_article.await_count == scheduler.MAX_GENERATION_ATTEMPTS == 3
        pipeline.service.save_article.assert_not_awaited()
        assert published == 0


class TestGenerationFailures:
    async def test_retries_after_a_generation_error_then_publishes(self, pipeline):
        # Regression test: ArticleGenerationError (e.g. unparseable LLM JSON) used
        # to propagate uncaught and crash the entire run, not just skip the topic.
        second = _make_article("art_good")
        pipeline.generator.generate_article.side_effect = [ArticleGenerationError("not valid JSON"), second]

        published = await scheduler.run_daily_pipeline(count=1)

        assert pipeline.generator.generate_article.await_count == 2
        pipeline.service.save_article.assert_awaited_once_with(second)
        assert published == 1

    async def test_waits_twice_as_long_after_each_failure(self, pipeline):
        second = _make_article("art_good")
        pipeline.generator.generate_article.side_effect = [
            ArticleGenerationError("first"), ArticleGenerationError("second"), second]

        await scheduler.run_daily_pipeline(count=1)

        waits = [call.args[0] for call in pipeline.sleep.await_args_list]
        assert waits == [scheduler.GENERATION_BACKOFF_SECONDS, 2 * scheduler.GENERATION_BACKOFF_SECONDS] == [5, 10]

    async def test_keeps_doubling_when_more_attempts_are_allowed(self, pipeline):
        pipeline.generator.generate_article.side_effect = ArticleGenerationError("always")

        with patch.object(scheduler, "MAX_GENERATION_ATTEMPTS", 5):
            await scheduler.run_daily_pipeline(count=1)

        assert [call.args[0] for call in pipeline.sleep.await_args_list] == [5, 10, 20, 40]

    async def test_does_not_wait_after_the_last_attempt(self, pipeline):
        pipeline.generator.generate_article.side_effect = ArticleGenerationError("always")

        published = await scheduler.run_daily_pipeline(count=1)

        assert pipeline.generator.generate_article.await_count == 3
        assert [call.args[0] for call in pipeline.sleep.await_args_list] == [5, 10]
        pipeline.service.save_article.assert_not_awaited()
        assert published == 0

    async def test_an_llm_provider_failure_is_retried_like_any_other(self, pipeline):
        second = _make_article("art_good")
        pipeline.generator.generate_article.side_effect = [RuntimeError("429 rate limited"), second]

        published = await scheduler.run_daily_pipeline(count=1)

        pipeline.service.save_article.assert_awaited_once_with(second)
        assert published == 1

    async def test_logs_each_failure_with_its_traceback(self, pipeline, caplog):
        pipeline.generator.generate_article.side_effect = [RuntimeError("429 rate limited"), _make_article()]

        with caplog.at_level(logging.INFO, logger="scrapper.scheduler"):
            await scheduler.run_daily_pipeline(count=1)

        [failure] = [r for r in caplog.records if "Generation failed" in r.getMessage()]
        assert failure.levelno == logging.WARNING
        assert "attempt 1 of 3" in failure.getMessage() and "429 rate limited" in failure.getMessage()
        assert isinstance(failure.exc_info[1], RuntimeError)

    async def test_says_so_at_error_level_when_it_gives_up(self, pipeline, caplog):
        pipeline.generator.generate_article.side_effect = ArticleGenerationError("always")

        with caplog.at_level(logging.INFO, logger="scrapper.scheduler"):
            await scheduler.run_daily_pipeline(count=1)

        [gave_up] = [r for r in caplog.records if "Giving up" in r.getMessage()]
        assert gave_up.levelno == logging.ERROR

    async def test_one_topic_failing_does_not_abort_the_rest_of_the_batch(self, pipeline):
        pipeline.topics.generate_topics.return_value = ["Always Broken Topic", "Fine Topic"]
        good = _make_article("art_good")
        pipeline.generator.generate_article.side_effect = [ArticleGenerationError("bad")] * 3 + [good]

        published = await scheduler.run_daily_pipeline(count=2)

        assert pipeline.generator.generate_article.await_count == 4
        pipeline.service.save_article.assert_awaited_once_with(good)
        assert published == 1


class TestUnexpectedFailures:
    async def test_a_failed_save_is_logged_with_its_traceback_and_the_batch_carries_on(self, pipeline, caplog):
        pipeline.topics.generate_topics.return_value = ["Unsavable Topic", "Fine Topic"]
        pipeline.service.save_article.side_effect = [RuntimeError("database down"), None]

        with caplog.at_level(logging.INFO, logger="scrapper.scheduler"):
            published = await scheduler.run_daily_pipeline(count=2)

        [unexpected] = [r for r in caplog.records if "Unexpected error" in r.getMessage()]
        assert unexpected.levelno == logging.ERROR
        assert "Unsavable Topic" in unexpected.getMessage()
        assert isinstance(unexpected.exc_info[1], RuntimeError)
        assert pipeline.service.save_article.await_count == 2
        assert published == 1

    async def test_a_failed_scrape_skips_only_that_topic(self, pipeline):
        pipeline.topics.generate_topics.return_value = ["Unreachable Topic", "Fine Topic"]
        pipeline.scraper.search_and_scrape.side_effect = [ConnectionError("no network"), ["scraped content"]]

        published = await scheduler.run_daily_pipeline(count=2)

        assert pipeline.generator.generate_article.await_count == 1
        assert published == 1


class TestQualityMetrics:
    async def test_logs_word_count_citation_count_and_generation_time_of_each_article(self, pipeline, caplog):
        pipeline.generator.generate_article.return_value = _real_article(words=1800, sections=4, citations=2)

        with caplog.at_level(logging.INFO, logger="scrapper.scheduler"), \
                patch("scrapper.scheduler.perf_counter", side_effect=[100.0, 103.46]):
            await scheduler.run_daily_pipeline(count=1)

        [entry] = [r for r in caplog.records if hasattr(r, "word_count")]
        assert entry.levelno == logging.INFO
        assert (entry.word_count, entry.citation_count, entry.section_count) == (1800, 2, 4)
        assert entry.generation_seconds == 3.5
        assert (entry.topic, entry.attempt, entry.valid) == ("Topic", 1, True)

    async def test_logs_them_for_an_article_that_is_rejected_too(self, pipeline, caplog):
        pipeline.generator.generate_article.side_effect = [_real_article(words=900), _real_article(words=1800)]
        pipeline.validator.validate.side_effect = [
            (False, ["word count 900 outside allowed range"]), (True, []), (True, []),
        ]

        with caplog.at_level(logging.INFO, logger="scrapper.scheduler"):
            await scheduler.run_daily_pipeline(count=1)

        first, second = [r for r in caplog.records if hasattr(r, "word_count")]
        assert (first.levelno, first.word_count, first.attempt, first.valid) == (logging.WARNING, 900, 1, False)
        assert (second.levelno, second.word_count, second.attempt, second.valid) == (logging.INFO, 1800, 2, True)

    async def test_times_each_attempt_separately(self, pipeline, caplog):
        pipeline.generator.generate_article.side_effect = [_real_article(), _real_article()]
        pipeline.validator.validate.side_effect = [(False, ["too short"]), (True, []), (True, [])]

        with caplog.at_level(logging.INFO, logger="scrapper.scheduler"), \
                patch("scrapper.scheduler.perf_counter", side_effect=[0.0, 2.0, 10.0, 17.0]):
            await scheduler.run_daily_pipeline(count=1)

        seconds = [r.generation_seconds for r in caplog.records if hasattr(r, "generation_seconds")]
        assert seconds == [2.0, 7.0]

    async def test_a_failed_attempt_logs_no_metrics(self, pipeline, caplog):
        pipeline.generator.generate_article.side_effect = ArticleGenerationError("always")

        with caplog.at_level(logging.INFO, logger="scrapper.scheduler"):
            await scheduler.run_daily_pipeline(count=1)

        assert not [r for r in caplog.records if hasattr(r, "word_count")]


class TestCriticLoop:
    async def test_approves_on_the_first_round_and_publishes(self, pipeline):
        published = await scheduler.run_daily_pipeline(count=1)

        pipeline.critic.review.assert_awaited_once()
        pipeline.generator.revise_article.assert_not_awaited()
        assert published == 1

    async def test_rejects_then_approves_after_one_revision(self, pipeline):
        pipeline.critic.review.side_effect = [_rejected(), _approved()]
        revised = _make_article("art_revised")
        pipeline.generator.revise_article.return_value = revised

        published = await scheduler.run_daily_pipeline(count=1)

        pipeline.generator.revise_article.assert_awaited_once()
        pipeline.service.save_article.assert_awaited_once_with(revised)
        assert published == 1

    async def test_never_publishes_an_article_the_critic_never_approves(self, pipeline):
        pipeline.critic.review.return_value = _rejected()

        published = await scheduler.run_daily_pipeline(count=1)

        # Bounded on both axes: CRITIC_MAX_ROUNDS reviews per attempt, MAX_GENERATION_ATTEMPTS attempts.
        assert pipeline.generator.generate_article.await_count == scheduler.MAX_GENERATION_ATTEMPTS
        assert pipeline.critic.review.await_count == scheduler.MAX_GENERATION_ATTEMPTS * scheduler.CRITIC_MAX_ROUNDS
        assert pipeline.generator.revise_article.await_count == (
            scheduler.MAX_GENERATION_ATTEMPTS * (scheduler.CRITIC_MAX_ROUNDS - 1)
        )
        pipeline.service.save_article.assert_not_awaited()
        assert published == 0

    async def test_a_revision_that_breaks_structural_validity_ends_the_round_early(self, pipeline):
        pipeline.critic.review.return_value = _rejected()
        # Per attempt: the outer pre-loop check passes, run_critic_loop's own top-of-round check
        # on that same (still-unrevised) draft also passes, and the one after the revision fails.
        pipeline.validator.validate.side_effect = [(True, []), (True, []), (False, ["word count too low"])] * 3

        published = await scheduler.run_daily_pipeline(count=1)

        # One review per attempt, not CRITIC_MAX_ROUNDS -- the broken revision short-circuits the round.
        assert pipeline.critic.review.await_count == scheduler.MAX_GENERATION_ATTEMPTS
        assert pipeline.generator.revise_article.await_count == scheduler.MAX_GENERATION_ATTEMPTS
        assert published == 0

    async def test_critic_disabled_skips_review_and_publishes_immediately(self, pipeline):
        with patch("scrapper.scheduler.get_llm_settings") as get_settings:
            get_settings.return_value.critic_enabled = False
            published = await scheduler.run_daily_pipeline(count=1)

        pipeline.critic.review.assert_not_awaited()
        pipeline.generator.revise_article.assert_not_awaited()
        pipeline.service.save_article.assert_awaited_once()
        assert published == 1

    async def test_image_sourcing_disabled_skips_it_and_publishes_with_no_images(self, pipeline):
        with patch("scrapper.scheduler.get_llm_settings") as get_settings:
            get_settings.return_value.image_sourcing_enabled = False
            published = await scheduler.run_daily_pipeline(count=1)

        pipeline.image_sourcer.source_images.assert_not_awaited()
        pipeline.service.save_article.assert_awaited_once()
        assert published == 1

    async def test_a_sourcing_failure_still_publishes_the_article(self, pipeline):
        pipeline.image_sourcer.source_images.side_effect = Exception("network error")

        published = await scheduler.run_daily_pipeline(count=1)

        pipeline.service.save_article.assert_awaited_once()
        assert published == 1

    async def test_critic_rounds_and_approval_are_logged(self, pipeline, caplog):
        pipeline.generator.generate_article.return_value = _real_article()
        pipeline.critic.review.side_effect = [_rejected(), _approved()]
        pipeline.generator.revise_article.return_value = _real_article()

        with caplog.at_level(logging.INFO, logger="scrapper.scheduler"):
            await scheduler.run_daily_pipeline(count=1)

        [entry] = [r for r in caplog.records if hasattr(r, "critic_rounds")]
        assert (entry.critic_rounds, entry.critic_approved) == (2, True)
        assert entry.critic_issue_categories == []


class TestRunCriticLoop:
    """Calls scheduler.run_critic_loop directly (the same entry point reprocess_articles.py
    uses) with hand-built collaborators, rather than going through run_daily_pipeline."""

    def _collaborators(self, images=None, review=None, cohesion_issues=None):
        critic = MagicMock()
        # A fresh CriticReview per call (not a shared return_value) -- run_critic_loop mutates
        # the review it gets back (folding in image issues), matching the real critic, which
        # parses a brand-new object from each LLM response rather than reusing one.
        critic.review = AsyncMock(side_effect=lambda *a, **k: review or _approved())
        critic.review_image_cohesion = AsyncMock(
            return_value=cohesion_issues if cohesion_issues is not None else []
        )
        generator = MagicMock()
        generator.revise_article = AsyncMock(return_value=_real_article())
        validator = MagicMock()
        validator.validate.return_value = (True, [])
        image_sourcer = MagicMock()
        image_sourcer.source_images = AsyncMock(return_value=images if images is not None else [])
        return critic, generator, validator, image_sourcer

    async def test_sources_images_before_the_first_round_when_no_initial_images_given(self):
        image = _image()
        critic, generator, validator, image_sourcer = self._collaborators(images=[image])

        result, review, rounds = await scheduler.run_critic_loop(
            _real_article(), ["scraped"], "Topic", generator, validator, critic, image_sourcer,
        )

        image_sourcer.source_images.assert_awaited_once_with(ANY, "Topic", exclude=frozenset())
        assert result.images == [image]
        assert result.image_url == image.url
        assert review.approved is True

    async def test_uses_initial_images_instead_of_sourcing_fresh(self):
        image = _image()
        critic, generator, validator, image_sourcer = self._collaborators()

        result, review, rounds = await scheduler.run_critic_loop(
            _real_article(), ["scraped"], "Topic", generator, validator, critic, image_sourcer,
            initial_images=[image],
        )

        image_sourcer.source_images.assert_not_awaited()
        assert result.images == [image]

    async def test_structural_invalidity_forces_a_revision_even_when_the_critic_approves(self):
        """critic.review only judges grounding/neutrality/etc., never word count -- this catches
        a too-short starting article (e.g. one reprocess_articles.py loads from before today's
        word-count bar) that the critic itself has no way to flag."""
        critic, generator, validator, image_sourcer = self._collaborators()
        validator.validate = MagicMock(side_effect=[
            (False, ["word count 200 outside allowed range [1300, 2200]"]),  # round 1, starting draft
            (True, []),  # right after the revision
            (True, []),  # round 2's top-of-round check on the now-fixed draft
        ])

        result, review, rounds = await scheduler.run_critic_loop(
            _real_article(), ["scraped"], "Topic", generator, validator, critic, image_sourcer,
        )

        generator.revise_article.assert_awaited_once()
        assert review.approved is True
        assert rounds == 2

    async def test_cohesion_failure_triggers_a_full_resource_not_text_revision(self):
        bad = _image(url="https://s/bad.jpg", source_url="https://commons.wikimedia.org/wiki/File:Bad.jpg")
        replacement = _image(
            url="https://s/replacement.jpg", source_url="https://commons.wikimedia.org/wiki/File:Repl.jpg"
        )
        critic, generator, validator, image_sourcer = self._collaborators()
        image_sourcer.source_images = AsyncMock(side_effect=[[bad], [replacement]])
        critic.review_image_cohesion = AsyncMock(side_effect=[[_cohesion_issue()], []])

        result, review, rounds = await scheduler.run_critic_loop(
            _real_article(), ["scraped"], "Topic", generator, validator, critic, image_sourcer,
        )

        generator.revise_article.assert_not_awaited()
        assert image_sourcer.source_images.await_count == 2
        second_call = image_sourcer.source_images.await_args_list[1]
        assert second_call.kwargs["exclude"] == {"File:Bad.jpg"}
        assert result.images == [replacement]
        assert review.approved is True
        assert rounds == 2

    async def test_a_text_and_image_issue_in_the_same_round_are_both_addressed(self):
        bad = _image(url="https://s/bad.jpg", source_url="https://commons.wikimedia.org/wiki/File:Bad.jpg")
        replacement = _image(
            url="https://s/good.jpg", source_url="https://commons.wikimedia.org/wiki/File:Good.jpg"
        )
        critic, generator, validator, image_sourcer = self._collaborators()
        image_sourcer.source_images = AsyncMock(side_effect=[[bad], [replacement]])
        critic.review = AsyncMock(side_effect=[_rejected(), _approved()])
        critic.review_image_cohesion = AsyncMock(side_effect=[[_cohesion_issue()], []])

        result, review, rounds = await scheduler.run_critic_loop(
            _real_article(), ["scraped"], "Topic", generator, validator, critic, image_sourcer,
        )

        generator.revise_article.assert_awaited_once()
        assert image_sourcer.source_images.await_count == 2
        assert result.images == [replacement]
        assert review.approved is True

    async def test_exclude_accumulates_across_rounds(self):
        # CRITIC_MAX_ROUNDS bumped to 3 so a second cohesion failure gets a chance to
        # trigger a second re-source, accumulating both rejected filenames in one `exclude`.
        first_bad = _image(url="https://s/a.jpg", source_url="https://commons.wikimedia.org/wiki/File:A.jpg")
        second_bad = _image(url="https://s/b.jpg", source_url="https://commons.wikimedia.org/wiki/File:B.jpg")
        replacement = _image(url="https://s/c.jpg", source_url="https://commons.wikimedia.org/wiki/File:C")
        critic, generator, validator, image_sourcer = self._collaborators()
        image_sourcer.source_images = AsyncMock(side_effect=[[first_bad], [second_bad], [replacement]])
        critic.review_image_cohesion = AsyncMock(side_effect=[[_cohesion_issue()], [_cohesion_issue()], []])

        with patch.object(scheduler, "CRITIC_MAX_ROUNDS", 3):
            result, review, rounds = await scheduler.run_critic_loop(
                _real_article(), ["scraped"], "Topic", generator, validator, critic, image_sourcer,
            )

        assert image_sourcer.source_images.await_count == 3
        third_call = image_sourcer.source_images.await_args_list[2]
        assert third_call.kwargs["exclude"] == {"File:A.jpg", "File:B.jpg"}
        assert result.images == [replacement]
