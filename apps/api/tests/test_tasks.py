import pytest
from fastapi.testclient import TestClient


def _create(client: TestClient, title: str) -> dict:
    response = client.post("/tasks", json={"title": title})
    assert response.status_code == 201
    return response.json()


def test_create_returns_task_with_defaults(client: TestClient) -> None:
    task = _create(client, "  write tests  ")

    assert task["id"] > 0
    assert task["title"] == "write tests"  # surrounding whitespace is stripped
    assert task["done"] is False
    assert task["created_at"]


def test_list_returns_tasks_in_id_order_with_paging(client: TestClient) -> None:
    for title in ("one", "two", "three"):
        _create(client, title)

    assert [t["title"] for t in client.get("/tasks").json()] == ["one", "two", "three"]
    page = client.get("/tasks", params={"limit": 1, "offset": 1}).json()
    assert [t["title"] for t in page] == ["two"]


def test_get_returns_task(client: TestClient) -> None:
    task = _create(client, "read me")

    response = client.get(f"/tasks/{task['id']}")

    assert response.status_code == 200
    assert response.json() == task


def test_patch_updates_only_given_fields(client: TestClient) -> None:
    task = _create(client, "original")

    done = client.patch(f"/tasks/{task['id']}", json={"done": True}).json()
    renamed = client.patch(f"/tasks/{task['id']}", json={"title": "renamed", "done": None}).json()

    assert done["done"] is True and done["title"] == "original"
    assert renamed["title"] == "renamed" and renamed["done"] is True


def test_delete_removes_task(client: TestClient) -> None:
    task = _create(client, "temporary")

    assert client.delete(f"/tasks/{task['id']}").status_code == 204
    assert client.get(f"/tasks/{task['id']}").status_code == 404


@pytest.mark.parametrize(
    ("method", "body"),
    [("get", None), ("patch", {"done": True}), ("delete", None)],
)
def test_missing_task_returns_404(client: TestClient, method: str, body: dict | None) -> None:
    response = client.request(method, "/tasks/999", json=body)

    assert response.status_code == 404
    assert response.json() == {"detail": "task not found"}


@pytest.mark.parametrize("title", ["", "   ", "x" * 201])
def test_invalid_title_returns_422(client: TestClient, title: str) -> None:
    assert client.post("/tasks", json={"title": title}).status_code == 422


def test_list_rejects_out_of_range_limit(client: TestClient) -> None:
    assert client.get("/tasks", params={"limit": 500}).status_code == 422
