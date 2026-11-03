import os
import tempfile
from datetime import datetime, timedelta

import pytest

os.environ["TASKSPHERE_DB"] = tempfile.mktemp(suffix=".db")

import app as app_module  # noqa: E402


@pytest.fixture()
def client():
    db_fd, db_path = tempfile.mkstemp(suffix=".db")
    app_module.DB_PATH = db_path
    app_module.init_db()
    app_module.app.config["TESTING"] = True
    with app_module.app.test_client() as client:
        yield client
    os.close(db_fd)
    os.unlink(db_path)


def iso(dt):
    return dt.isoformat()


def test_healthz(client):
    res = client.get("/healthz")
    assert res.status_code == 200
    assert res.get_json()["status"] == "ok"

def test_health_endpoint(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.get_json()["status"] == "ok"


def test_metrics_endpoint(client):
    due = iso(datetime.utcnow() + timedelta(days=1))
    client.post("/api/tasks", json={"title": "Metric task", "due_at": due})
    client.get("/health")
    res = client.get("/metrics")
    assert res.status_code == 200
    body = res.get_data(as_text=True)
    assert "tasksphere_http_requests_total" in body
    assert 'tasksphere_tasks{status="due_soon"}' in body
    
    
def test_index_page_loads(client):
    res = client.get("/")
    assert res.status_code == 200
    assert b"TaskSphere" in res.data


def test_create_task_success(client):
    due = iso(datetime.utcnow() + timedelta(days=5))
    res = client.post(
        "/api/tasks",
        json={"title": "Project PPT", "due_at": due, "reminder_offset": "1_day"},
    )
    assert res.status_code == 201
    body = res.get_json()
    assert body["title"] == "Project PPT"
    assert body["completed"] is False
    assert body["status"] in ("scheduled", "upcoming")


def test_create_task_missing_title(client):
    due = iso(datetime.utcnow() + timedelta(days=1))
    res = client.post("/api/tasks", json={"due_at": due})
    assert res.status_code == 400
    assert "title" in res.get_json()["error"]


def test_create_task_missing_due_at(client):
    res = client.post("/api/tasks", json={"title": "No due date"})
    assert res.status_code == 400


def test_create_task_bad_due_at_format(client):
    res = client.post("/api/tasks", json={"title": "Bad date", "due_at": "not-a-date"})
    assert res.status_code == 400


def test_create_task_invalid_reminder_offset(client):
    due = iso(datetime.utcnow() + timedelta(days=1))
    res = client.post(
        "/api/tasks", json={"title": "Bad reminder", "due_at": due, "reminder_offset": "5_years"}
    )
    assert res.status_code == 400


def test_list_tasks(client):
    due = iso(datetime.utcnow() + timedelta(days=2))
    client.post("/api/tasks", json={"title": "Task A", "due_at": due})
    client.post("/api/tasks", json={"title": "Task B", "due_at": due})
    res = client.get("/api/tasks")
    assert res.status_code == 200
    body = res.get_json()
    assert len(body) == 2


def test_update_task(client):
    due = iso(datetime.utcnow() + timedelta(days=2))
    create = client.post("/api/tasks", json={"title": "Old title", "due_at": due})
    task_id = create.get_json()["id"]

    new_due = iso(datetime.utcnow() + timedelta(days=10))
    res = client.put(
        f"/api/tasks/{task_id}", json={"title": "New title", "due_at": new_due}
    )
    assert res.status_code == 200
    body = res.get_json()
    assert body["title"] == "New title"


def test_update_nonexistent_task(client):
    res = client.put("/api/tasks/9999", json={"title": "x", "due_at": iso(datetime.utcnow())})
    assert res.status_code == 404


def test_toggle_complete(client):
    due = iso(datetime.utcnow() + timedelta(days=1))
    create = client.post("/api/tasks", json={"title": "Finish lab", "due_at": due})
    task_id = create.get_json()["id"]

    res = client.patch(f"/api/tasks/{task_id}/complete")
    assert res.status_code == 200
    body = res.get_json()
    assert body["completed"] is True
    assert body["status"] == "completed"

    res2 = client.patch(f"/api/tasks/{task_id}/complete")
    assert res2.get_json()["completed"] is False


def test_delete_task(client):
    due = iso(datetime.utcnow() + timedelta(days=1))
    create = client.post("/api/tasks", json={"title": "Delete me", "due_at": due})
    task_id = create.get_json()["id"]

    res = client.delete(f"/api/tasks/{task_id}")
    assert res.status_code == 200

    res2 = client.get("/api/tasks")
    assert all(t["id"] != task_id for t in res2.get_json())


def test_delete_nonexistent_task(client):
    res = client.delete("/api/tasks/12345")
    assert res.status_code == 404


def test_status_overdue():
    now = datetime(2026, 1, 10, 12, 0)
    due = iso(datetime(2026, 1, 10, 10, 0))
    status = app_module.compute_status(due, "1_day", completed=0, now=now)
    assert status == "overdue"


def test_status_due_soon():
    now = datetime(2026, 1, 10, 12, 0)
    due = iso(datetime(2026, 1, 11, 0, 0))
    status = app_module.compute_status(due, "1_day", completed=0, now=now)
    assert status == "due_soon"


def test_status_upcoming():
    now = datetime(2026, 1, 10, 12, 0)
    due = iso(datetime(2026, 1, 13, 0, 0))
    status = app_module.compute_status(due, "1_day", completed=0, now=now)
    assert status == "upcoming"


def test_status_scheduled():
    now = datetime(2026, 1, 1, 12, 0)
    due = iso(datetime(2026, 2, 1, 12, 0))
    status = app_module.compute_status(due, "1_day", completed=0, now=now)
    assert status == "scheduled"


def test_status_completed_overrides_everything():
    now = datetime(2026, 1, 10, 12, 0)
    due = iso(datetime(2026, 1, 1, 0, 0))
    status = app_module.compute_status(due, "1_day", completed=1, now=now)
    assert status == "completed"