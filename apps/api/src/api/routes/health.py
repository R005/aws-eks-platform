"""Liveness, readiness and metrics endpoints."""

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from api.db import get_session

logger = logging.getLogger(__name__)
router = APIRouter(tags=["health"])


# async on purpose: it runs on the event loop, so a saturated threadpool can't fail liveness.
@router.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/readyz")
def readyz(response: Response, session: Annotated[Session, Depends(get_session)]) -> dict:
    try:
        session.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        logger.warning("readiness check failed", extra={"error": type(exc).__name__})
        response.status_code = 503
        return {"status": "unavailable"}
    return {"status": "ok"}


@router.get("/metrics", include_in_schema=False)
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
