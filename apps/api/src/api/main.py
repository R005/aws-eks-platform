"""Application factory."""

import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from sqlalchemy.orm import sessionmaker

from api.config import Settings, get_settings
from api.db import make_engine
from api.metrics import HTTP_LATENCY, HTTP_REQUESTS
from api.routes import debug, health, tasks

logger = logging.getLogger("api")

# Probe and scrape traffic is logged at DEBUG so it doesn't drown the access log.
_QUIET_PATHS = {"/healthz", "/readyz", "/metrics"}


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    engine = make_engine(settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        logger.info("api started", extra={"debug_endpoints": settings.enable_debug_endpoints})
        yield
        # Runs after uvicorn has stopped accepting connections and drained in-flight requests.
        logger.info("api shutting down, closing database pool")
        engine.dispose()

    app = FastAPI(title="task-tracker api", version="0.1.0", lifespan=lifespan)
    app.state.sessionmaker = sessionmaker(engine, expire_on_commit=False)

    @app.middleware("http")
    async def observe(request: Request, call_next):
        start = time.perf_counter()
        status_code = 500
        try:
            response = await call_next(request)
            status_code = response.status_code
            return response
        finally:
            duration = time.perf_counter() - start
            route = request.scope.get("route")
            route_path = route.path if route else "unmatched"
            HTTP_REQUESTS.labels(request.method, route_path, str(status_code)).inc()
            HTTP_LATENCY.labels(request.method, route_path).observe(duration)
            logger.log(
                logging.DEBUG if request.url.path in _QUIET_PATHS else logging.INFO,
                "request",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status": status_code,
                    "duration_ms": round(duration * 1000, 2),
                },
            )

    app.include_router(health.router)
    app.include_router(tasks.router)
    if settings.enable_debug_endpoints:
        app.include_router(debug.router)
    return app
