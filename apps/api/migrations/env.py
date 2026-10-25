"""Alembic environment: same Settings and JSON logging as the api."""

import logging.config

from alembic import context
from sqlalchemy import create_engine
from sqlalchemy.pool import NullPool

from api.config import get_settings
from api.log_config import logging_config
from api.models import Base

settings = get_settings()
logging.config.dictConfig(logging_config(settings.log_level))
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Render SQL without connecting (`alembic upgrade head --sql`)."""
    context.configure(
        url=settings.database_url.render_as_string(hide_password=True),
        target_metadata=target_metadata,
        literal_binds=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    engine = create_engine(settings.database_url, poolclass=NullPool)
    with engine.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
