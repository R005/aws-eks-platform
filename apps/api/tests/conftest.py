"""Shared fixtures: the app wired to an in-memory SQLite database instead of Postgres."""

from collections.abc import Callable, Iterator
from contextlib import ExitStack

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from api.config import Settings
from api.db import get_session
from api.main import create_app
from api.models import Base


@pytest.fixture
def settings() -> Settings:
    # The Postgres engine built from these is never connected; get_session is overridden.
    return Settings(
        db_host="unused",
        db_name="tasks",
        db_user="tasks",
        db_password="not-a-real-password",
        enable_debug_endpoints=False,
    )


@pytest.fixture
def session_factory() -> Iterator[sessionmaker[Session]]:
    # StaticPool + check_same_thread=False: one shared in-memory DB across the threadpool.
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(engine)  # tests only; real schemas come from Alembic
    yield sessionmaker(engine, expire_on_commit=False)
    engine.dispose()


@pytest.fixture
def make_client(
    settings: Settings, session_factory: sessionmaker[Session]
) -> Iterator[Callable[..., TestClient]]:
    """Build a TestClient; keyword arguments override settings (e.g. enable_debug_endpoints)."""
    with ExitStack() as stack:

        def _make(**overrides) -> TestClient:
            app = create_app(settings.model_copy(update=overrides))

            def _session() -> Iterator[Session]:
                with session_factory() as session:
                    yield session

            app.dependency_overrides[get_session] = _session
            return stack.enter_context(TestClient(app))

        yield _make


@pytest.fixture
def client(make_client: Callable[..., TestClient]) -> TestClient:
    return make_client()
