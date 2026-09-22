"""Unit tests for the pipeline's command-line entry point: its arguments, its logging setup and its exit status."""

from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest

import scrapper_main


@pytest.fixture
def run():
    with patch("scrapper_main.run_daily_pipeline", new_callable=AsyncMock) as pipeline, \
            patch("scrapper_main.configure_logging") as logging_setup:
        pipeline.return_value = 1
        yield SimpleNamespace(pipeline=pipeline, logging_setup=logging_setup)


class TestMain:
    def test_publishing_every_requested_article_exits_zero(self, run):
        run.pipeline.return_value = 3

        assert scrapper_main.main(["--count", "3"]) == 0

    def test_publishing_fewer_than_requested_fails(self, run):
        run.pipeline.return_value = 2

        assert scrapper_main.main(["--count", "3"]) == 1

    def test_publishing_nothing_fails(self, run):
        run.pipeline.return_value = 0

        assert scrapper_main.main([]) == 1

    def test_publishes_one_article_unless_told_otherwise(self, run):
        scrapper_main.main([])

        run.pipeline.assert_awaited_once_with(count=1)

    def test_passes_the_requested_count_on(self, run):
        run.pipeline.return_value = 5

        scrapper_main.main(["--count", "5"])

        run.pipeline.assert_awaited_once_with(count=5)

    def test_logs_the_pipeline_backend_and_common_at_info_by_default(self, run, monkeypatch):
        monkeypatch.delenv("LOG_LEVEL", raising=False)

        scrapper_main.main([])

        run.logging_setup.assert_called_once_with("INFO", "scrapper", "backend", "common")

    def test_takes_the_log_level_from_the_environment(self, run, monkeypatch):
        monkeypatch.setenv("LOG_LEVEL", "debug")

        scrapper_main.main([])

        assert run.logging_setup.call_args.args[0] == "DEBUG"

    def test_sets_up_logging_before_running_anything(self, run):
        order = []
        run.logging_setup.side_effect = lambda *a: order.append("logging")
        run.pipeline.side_effect = lambda **k: order.append("pipeline") or 1

        scrapper_main.main([])

        assert order == ["logging", "pipeline"]
