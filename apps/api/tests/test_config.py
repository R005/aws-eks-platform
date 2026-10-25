import pytest

from api.config import get_settings

PASSWORD = "p@ss/word#with:special"


@pytest.fixture
def db_env(monkeypatch: pytest.MonkeyPatch) -> pytest.MonkeyPatch:
    for name, value in {
        "DB_HOST": "db",
        "DB_NAME": "tasks",
        "DB_USER": "tasks",
        "DB_PASSWORD": PASSWORD,
    }.items():
        monkeypatch.setenv(name, value)
    return monkeypatch


def test_settings_are_read_from_environment(db_env: pytest.MonkeyPatch) -> None:
    settings = get_settings()

    assert settings.db_port == 5432
    assert settings.enable_debug_endpoints is False
    # special characters are escaped in the URL, and the password never shows in repr
    assert settings.database_url.password == PASSWORD
    assert PASSWORD not in repr(settings)


def test_config_error_names_fields_without_leaking_password(db_env: pytest.MonkeyPatch) -> None:
    db_env.delenv("DB_NAME")

    with pytest.raises(SystemExit) as exc:
        get_settings()

    message = str(exc.value)
    assert "DB_NAME" in message
    assert PASSWORD not in message
