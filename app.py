import os
import sqlite3
from datetime import datetime, timedelta
from flask import Flask, request, jsonify, render_template, g

app = Flask(__name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.environ.get("TASKSPHERE_DB", os.path.join(BASE_DIR, "tasksphere.db"))

REMINDER_OFFSETS = {
    "10_min": timedelta(minutes=10),
    "1_hour": timedelta(hours=1),
    "1_day": timedelta(days=1),
    "3_days": timedelta(days=3),
}


def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(exception=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    db = sqlite3.connect(DB_PATH)
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT DEFAULT '',
            due_at TEXT NOT NULL,
            reminder_offset TEXT NOT NULL DEFAULT '1_day',
            completed INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        )
        """
    )
    db.commit()
    db.close()


def compute_status(due_at_str, reminder_offset, completed, now=None):
    """
    Compute reminder status on read - no scheduler needed.
    Returns one of: completed, overdue, due_soon, upcoming, scheduled
    """
    if completed:
        return "completed"

    now = now or datetime.utcnow()
    due_at = datetime.fromisoformat(due_at_str)
    offset = REMINDER_OFFSETS.get(reminder_offset, timedelta(days=1))
    reminder_time = due_at - offset

    if now > due_at:
        return "overdue"
    elif now >= reminder_time:
        return "due_soon"
    elif now >= reminder_time - timedelta(days=3):
        return "upcoming"
    else:
        return "scheduled"


def human_due_text(due_at_str, now=None):
    now = now or datetime.utcnow()
    due_at = datetime.fromisoformat(due_at_str)
    delta = due_at - now
    days = delta.days
    seconds = delta.seconds

    if delta.total_seconds() < 0:
        overdue_by = now - due_at
        if overdue_by.days >= 1:
            return f"Overdue by {overdue_by.days}d"
        hours = overdue_by.seconds // 3600
        return f"Overdue by {max(hours,1)}h"
    if days == 0 and seconds < 3600:
        mins = seconds // 60
        return f"Due in {max(mins,1)} min"
    if days == 0:
        hours = seconds // 3600
        return f"Due in {hours}h"
    if days == 1:
        return "Due tomorrow"
    return f"Due in {days} days"


def row_to_task(row, now=None):
    status = compute_status(row["due_at"], row["reminder_offset"], row["completed"], now)
    return {
        "id": row["id"],
        "title": row["title"],
        "description": row["description"],
        "due_at": row["due_at"],
        "reminder_offset": row["reminder_offset"],
        "completed": bool(row["completed"]),
        "status": status,
        "due_text": "Completed" if row["completed"] else human_due_text(row["due_at"], now),
    }


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/tasks", methods=["GET"])
def list_tasks():
    db = get_db()
    rows = db.execute("SELECT * FROM tasks ORDER BY due_at ASC").fetchall()
    tasks = [row_to_task(r) for r in rows]
    return jsonify(tasks)


@app.route("/api/tasks", methods=["POST"])
def create_task():
    data = request.get_json(silent=True) or {}
    title = (data.get("title") or "").strip()
    due_at = data.get("due_at")
    reminder_offset = data.get("reminder_offset", "1_day")
    description = data.get("description", "")

    if not title:
        return jsonify({"error": "title is required"}), 400
    if not due_at:
        return jsonify({"error": "due_at is required"}), 400
    try:
        datetime.fromisoformat(due_at)
    except ValueError:
        return jsonify({"error": "due_at must be ISO format e.g. 2026-08-25T14:00"}), 400
    if reminder_offset not in REMINDER_OFFSETS:
        return jsonify({"error": "invalid reminder_offset"}), 400

    db = get_db()
    cur = db.execute(
        "INSERT INTO tasks (title, description, due_at, reminder_offset, completed, created_at) "
        "VALUES (?, ?, ?, ?, 0, ?)",
        (title, description, due_at, reminder_offset, datetime.utcnow().isoformat()),
    )
    db.commit()
    row = db.execute("SELECT * FROM tasks WHERE id = ?", (cur.lastrowid,)).fetchone()
    return jsonify(row_to_task(row)), 201


@app.route("/api/tasks/<int:task_id>", methods=["PUT"])
def update_task(task_id):
    db = get_db()
    row = db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if row is None:
        return jsonify({"error": "task not found"}), 404

    data = request.get_json(silent=True) or {}
    title = data.get("title", row["title"])
    description = data.get("description", row["description"])
    due_at = data.get("due_at", row["due_at"])
    reminder_offset = data.get("reminder_offset", row["reminder_offset"])

    if not title or not str(title).strip():
        return jsonify({"error": "title is required"}), 400
    try:
        datetime.fromisoformat(due_at)
    except ValueError:
        return jsonify({"error": "due_at must be ISO format"}), 400
    if reminder_offset not in REMINDER_OFFSETS:
        return jsonify({"error": "invalid reminder_offset"}), 400

    db.execute(
        "UPDATE tasks SET title=?, description=?, due_at=?, reminder_offset=? WHERE id=?",
        (title, description, due_at, reminder_offset, task_id),
    )
    db.commit()
    row = db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    return jsonify(row_to_task(row))


@app.route("/api/tasks/<int:task_id>/complete", methods=["PATCH"])
def toggle_complete(task_id):
    db = get_db()
    row = db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if row is None:
        return jsonify({"error": "task not found"}), 404
    new_val = 0 if row["completed"] else 1
    db.execute("UPDATE tasks SET completed=? WHERE id=?", (new_val, task_id))
    db.commit()
    row = db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    return jsonify(row_to_task(row))


@app.route("/api/tasks/<int:task_id>", methods=["DELETE"])
def delete_task(task_id):
    db = get_db()
    row = db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if row is None:
        return jsonify({"error": "task not found"}), 404
    db.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
    db.commit()
    return jsonify({"deleted": task_id})


@app.route("/healthz")
def healthz():
    return jsonify({"status": "ok"})


init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)