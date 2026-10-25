"""Settings loaded from environment variables only."""

from pydantic import SecretStr, ValidationError
from pydantic_settings import BaseSettings
from sqlalchemy.engine import URL


class Settings(BaseSettings):
    # Field names map to upper-case env vars: db_host <- DB_HOST, and so on.
    db_host: str
    db_port: int = 5432
    db_name: str
    db_user: str
    db_password: SecretStr  # required, no default; SecretStr masks it in repr and logs
    db_connect_timeout: int = 3
    log_level: str = "INFO"
    enable_debug_endpoints: bool = False

    @property
    def database_url(self) -> URL:
        # URL.create escapes special characters in the password, unlike an f-string DSN.
        return URL.create(
            "postgresql+psycopg",
            username=self.db_user,
            password=self.db_password.get_secret_value(),
            host=self.db_host,
            port=self.db_port,
            database=self.db_name,
        )


def get_settings() -> Settings:
    try:
        return Settings()
    except ValidationError as exc:
        # pydantic's default message echoes input values, which could include DB_PASSWORD.
        problems = "; ".join(
            f"{'.'.join(map(str, err['loc'])).upper()}: {err['msg']}"
            for err in exc.errors(include_input=False)
        )
        raise SystemExit(f"invalid configuration: {problems}") from None
