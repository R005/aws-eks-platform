"""Entrypoint: `python -m api`."""

import uvicorn

from api.config import get_settings
from api.log_config import logging_config
from api.main import create_app


def main() -> None:
    settings = get_settings()
    # On SIGTERM uvicorn drains in-flight requests for up to 20s, inside the pod's grace period.
    uvicorn.run(
        create_app(settings),
        host="0.0.0.0",
        port=8000,
        log_config=logging_config(settings.log_level),
        access_log=False,
        timeout_graceful_shutdown=20,
    )


# Required: the CPU drill uses multiprocessing "spawn", which re-imports this module.
if __name__ == "__main__":
    main()
