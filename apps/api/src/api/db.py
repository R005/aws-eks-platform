"""Database engine and per-request session."""

from collections.abc import Iterator

from fastapi import Request
from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session

from api.config import Settings


def make_engine(settings: Settings) -> Engine:
    return create_engine(
        settings.database_url,
        pool_size=5,
        max_overflow=5,
        pool_pre_ping=True,  # drop dead connections (for example after a Postgres restart)
        connect_args={"connect_timeout": settings.db_connect_timeout},
    )


def get_session(request: Request) -> Iterator[Session]:
    with request.app.state.sessionmaker() as session:
        yield session
