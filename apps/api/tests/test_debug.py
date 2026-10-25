from collections.abc import Callable

import pytest
from fastapi.testclient import TestClient

from api.routes import debug


@pytest.fixture
def started(monkeypatch: pytest.MonkeyPatch) -> list[tuple]:
    """Record load starts instead of actually burning CPU or memory."""
    calls: list[tuple] = []
    monkeypatch.setattr(debug, "start_cpu_burn", lambda *args: calls.append(("cpu", *args)))
    monkeypatch.setattr(debug, "start_memory_hold", lambda *args: calls.append(("memory", *args)))
    return calls


def test_debug_endpoints_are_404_when_disabled(client: TestClient, started: list) -> None:
    assert client.post("/debug/load/cpu").status_code == 404
    assert client.post("/debug/load/memory").status_code == 404
    assert started == []


def test_cpu_load_starts_when_enabled(
    make_client: Callable[..., TestClient], started: list
) -> None:
    client = make_client(enable_debug_endpoints=True)

    response = client.post("/debug/load/cpu", params={"seconds": 5, "workers": 2})

    assert response.status_code == 202
    assert started == [("cpu", 5, 2)]


def test_memory_load_starts_when_enabled(
    make_client: Callable[..., TestClient], started: list
) -> None:
    client = make_client(enable_debug_endpoints=True)

    response = client.post("/debug/load/memory", params={"mb": 64, "seconds": 5})

    assert response.status_code == 202
    assert started == [("memory", 64, 5)]


@pytest.mark.parametrize(
    ("path", "params"),
    [
        ("/debug/load/cpu", {"seconds": debug.MAX_SECONDS + 1}),
        ("/debug/load/cpu", {"workers": debug.MAX_WORKERS + 1}),
        ("/debug/load/memory", {"mb": debug.MAX_MB + 1}),
    ],
)
def test_load_above_caps_is_rejected(
    make_client: Callable[..., TestClient], started: list, path: str, params: dict
) -> None:
    client = make_client(enable_debug_endpoints=True)

    assert client.post(path, params=params).status_code == 422
    assert started == []
