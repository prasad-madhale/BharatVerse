"""JSON-line logging for the backend, with any `extra` fields as keys of their own."""

import json
import logging
import sys
from datetime import datetime, timezone

_STANDARD_FIELDS = set(logging.makeLogRecord({}).__dict__) | {"message", "asctime"}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "time": datetime.fromtimestamp(record.created, timezone.utc).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        entry.update({key: value for key, value in record.__dict__.items() if key not in _STANDARD_FIELDS})
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def configure_logging(level: str) -> None:
    """Sends the backend's own logs to stdout as JSON lines at `level`; other libraries keep their defaults."""
    logger = logging.getLogger("backend")
    logger.setLevel(level)
    if not logger.handlers and not logging.getLogger().handlers:  # a host that already logs (pytest) keeps its own
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(JsonFormatter())
        logger.addHandler(handler)
