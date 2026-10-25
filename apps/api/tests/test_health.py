from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError

from api.db import get_session


class _UnreachableDatabase:
    def execute(self, *args, **kwargs):
        raise OperationalError("SELECT 1", {}, Exception("connection refused"))


def test_healthz_has_no_dependencies(client: TestClient) -> None:
    client.app.dependency_overrides[get_session] = _UnreachableDatabase

    response = client.get("/healthz")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readyz_ok_when_database_answers(client: TestClient) -> None:
    response = client.get("/readyz")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readyz_503_when_database_is_down(client: TestClient) -> None:
    client.app.dependency_overrides[get_session] = _UnreachableDatabase

    response = client.get("/readyz")

    assert response.status_code == 503
    assert response.json() == {"status": "unavailable"}


def test_metrics_exposes_request_counter_by_route_template(client: TestClient) -> None:
    client.get("/tasks/999")

    response = client.get("/metrics")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert 'http_requests_total{method="GET",route="/tasks/{task_id}",status="404"}' in (
        response.text
    )
