"""Structured JSON logging to stdout."""

import json
import logging
from datetime import UTC, datetime

# Attributes every LogRecord has; anything else on a record came from `extra=`.
_STANDARD_ATTRS = set(vars(logging.makeLogRecord({}))) | {"message", "asctime", "color_message"}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        payload.update({k: v for k, v in vars(record).items() if k not in _STANDARD_ATTRS})
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def logging_config(level: str) -> dict:
    """dictConfig that routes our loggers, uvicorn and alembic through one JSON handler."""
    return {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {"json": {"()": JsonFormatter}},
        "handlers": {
            "stdout": {
                "class": "logging.StreamHandler",
                "stream": "ext://sys.stdout",
                "formatter": "json",
            }
        },
        "root": {"handlers": ["stdout"], "level": level.upper()},
        # Uvicorn's loggers propagate to root; its access log is replaced by our middleware.
        "loggers": {
            "uvicorn": {"handlers": [], "propagate": True},
            "uvicorn.error": {"handlers": [], "propagate": True},
            "uvicorn.access": {"handlers": [], "propagate": False},
        },
    }
