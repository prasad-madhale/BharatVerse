"""Unit tests for the JSON-line logging the backend and the pipeline share."""

import json
import logging
from contextlib import contextmanager
from datetime import datetime

import pytest

from common.logging_config import JsonFormatter, configure_logging


def record(message="hello", level=logging.INFO, args=(), exc_info=None, **extra):
    return logging.getLogger("backend.test").makeRecord(
        "backend.test", level, __file__, 1, message, args, exc_info, extra=extra)


class TestJsonFormatter:
    def test_writes_one_json_object_with_the_standard_keys(self):
        line = JsonFormatter().format(record("hello %s", args=("world",), level=logging.WARNING))

        entry = json.loads(line)
        assert "\n" not in line
        assert entry["message"] == "hello world"
        assert entry["level"] == "WARNING"
        assert entry["logger"] == "backend.test"
        assert datetime.fromisoformat(entry["time"]).utcoffset().total_seconds() == 0

    def test_adds_extra_fields_as_keys_of_their_own(self):
        entry = json.loads(JsonFormatter().format(record(status=404, path="/nope")))

        assert entry["status"] == 404
        assert entry["path"] == "/nope"

    def test_leaves_out_the_logging_internals(self):
        entry = json.loads(JsonFormatter().format(record()))

        assert set(entry) == {"time", "level", "logger", "message"}

    def test_includes_the_traceback_of_an_exception(self):
        try:
            raise ValueError("bad input")
        except ValueError:
            import sys
            line = JsonFormatter().format(record("failed", level=logging.ERROR, exc_info=sys.exc_info()))

        assert "ValueError: bad input" in json.loads(line)["exception"]

    def test_survives_a_value_json_cannot_hold(self):
        entry = json.loads(JsonFormatter().format(record(when=datetime(2026, 9, 20), thing=object())))

        assert entry["when"] == "2026-09-20 00:00:00"
        assert entry["thing"].startswith("<object object")


@pytest.fixture
def clean_logging():
    """Gives the test backend and scrapper loggers with no handlers, and puts them back after; yields the backend one."""
    loggers = [logging.getLogger(name) for name in ("backend", "scrapper")]
    saved = [(logger.handlers[:], logger.level) for logger in loggers]
    for logger in loggers:
        logger.handlers = []
    yield loggers[0]
    for logger, (handlers, level) in zip(loggers, saved):
        logger.handlers, logger.level = handlers, level


@contextmanager
def bare_root_logger():
    """A root logger with no handlers, as under uvicorn; pytest adds its own again for each test, so do it in the test."""
    root = logging.getLogger()
    handlers, root.handlers = root.handlers, []
    try:
        yield root
    finally:
        root.handlers = handlers


class TestConfigureLogging:
    def test_sends_backend_logs_to_stdout_as_json_at_the_level(self, clean_logging, capsys):
        with bare_root_logger():
            configure_logging("WARNING", "backend")

            logging.getLogger("backend.services.thing").info("too quiet")
            logging.getLogger("backend.services.thing").warning("loud enough")

        lines = capsys.readouterr().out.strip().splitlines()
        assert [json.loads(line)["message"] for line in lines] == ["loud enough"]

    def test_leaves_other_libraries_at_their_defaults(self, clean_logging, capsys):
        with bare_root_logger():
            configure_logging("DEBUG", "backend")

            logging.getLogger("httpx").info("a library talking")

        assert capsys.readouterr().out == ""

    def test_is_safe_to_call_again(self, clean_logging, capsys):
        with bare_root_logger():
            configure_logging("INFO", "backend")
            configure_logging("INFO", "backend")

            logging.getLogger("backend").info("once")

        assert len(capsys.readouterr().out.strip().splitlines()) == 1

    def test_configures_every_logger_it_is_given(self, clean_logging, capsys):
        with bare_root_logger():
            configure_logging("INFO", "backend", "scrapper")

            logging.getLogger("backend.api").info("from the backend")
            logging.getLogger("scrapper.scheduler").info("from the pipeline")
            logging.getLogger("elsewhere").info("from another library")

        lines = capsys.readouterr().out.strip().splitlines()
        assert [json.loads(line)["message"] for line in lines] == ["from the backend", "from the pipeline"]

    def test_leaves_a_host_that_already_logs_alone(self, clean_logging):
        with bare_root_logger() as root:
            root.addHandler(logging.NullHandler())

            configure_logging("INFO", "backend")

        assert clean_logging.handlers == []
        assert clean_logging.level == logging.INFO
