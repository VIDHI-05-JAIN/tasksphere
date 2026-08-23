const STATUS_ICON = {
  overdue: "⚠️",
  due_soon: "⏰",
  upcoming: "📌",
  scheduled: "🗓️",
  completed: "✅",
};

const REMINDER_LABEL = {
  "10_min": "10 min before",
  "1_hour": "1 hour before",
  "1_day": "1 day before",
  "3_days": "3 days before",
};

let allTasks = [];
let currentFilter = "all";
let editingId = null;

const el = (id) => document.getElementById(id);

async function api(path, options = {}) {
  const res = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || "Request failed");
  return data;
}

async function loadTasks() {
  try {
    allTasks = await api("/api/tasks");
    renderDeadlines();
    renderBoard();
  } catch (err) {
    console.error(err);
  }
}

function renderDeadlines() {
  const list = el("deadlinesList");
  const sorted = [...allTasks].sort((a, b) => {
    const order = { overdue: 0, due_soon: 1, upcoming: 2, scheduled: 3, completed: 4 };
    return order[a.status] - order[b.status];
  });
  const top = sorted.slice(0, 6);

  if (top.length === 0) {
    list.innerHTML = `<div class="deadlines-empty">Board is empty. Add a task to see it here.</div>`;
    return;
  }

  list.innerHTML = top
    .map(
      (t) => `
    <div class="deadline-row status-${t.status}">
      <span class="deadline-icon">${STATUS_ICON[t.status]}</span>
      <span class="deadline-title">${escapeHtml(t.title)}</span>
      <span class="deadline-due">${escapeHtml(t.due_text)}</span>
    </div>`
    )
    .join("");
}

function renderBoard() {
  const rowsContainer = el("taskRows");
  const emptyState = el("emptyState");

  let visible = allTasks;
  if (currentFilter === "active") visible = allTasks.filter((t) => !t.completed);
  if (currentFilter === "completed") visible = allTasks.filter((t) => t.completed);

  if (visible.length === 0) {
    rowsContainer.innerHTML = "";
    emptyState.style.display = "block";
    return;
  }
  emptyState.style.display = "none";

  rowsContainer.innerHTML = visible
    .map(
      (t) => `
    <div class="board-row ${t.completed ? "row-completed" : ""}">
      <span class="status-chip status-${t.status}">${t.status.replace("_", " ")}</span>
      <span>
        <span class="row-title">${escapeHtml(t.title)}</span>
        ${t.description ? `<span class="row-desc">${escapeHtml(t.description)}</span>` : ""}
      </span>
      <span class="row-due">${escapeHtml(t.due_text)}</span>
      <span class="row-reminder">${REMINDER_LABEL[t.reminder_offset]}</span>
      <span class="row-actions">
        <button class="btn-small" onclick="toggleComplete(${t.id})">${t.completed ? "Undo" : "Done"}</button>
        <button class="btn-small" onclick="editTask(${t.id})">Edit</button>
        <button class="btn-small danger" onclick="deleteTask(${t.id})">Del</button>
      </span>
    </div>`
    )
    .join("");
}

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str ?? "";
  return div.innerHTML;
}

async function toggleComplete(id) {
  await api(`/api/tasks/${id}/complete`, { method: "PATCH" });
  loadTasks();
}

async function deleteTask(id) {
  if (!confirm("Delete this task?")) return;
  await api(`/api/tasks/${id}`, { method: "DELETE" });
  loadTasks();
}

function editTask(id) {
  const task = allTasks.find((t) => t.id === id);
  if (!task) return;
  editingId = id;
  el("taskId").value = id;
  el("title").value = task.title;
  el("description").value = task.description || "";
  el("dueAt").value = task.due_at.slice(0, 16);
  el("reminderOffset").value = task.reminder_offset;
  el("formTitle").textContent = "✎ Edit Task";
  el("submitBtn").textContent = "Save Changes";
  el("cancelEditBtn").style.display = "inline-block";
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function resetForm() {
  editingId = null;
  el("taskForm").reset();
  el("taskId").value = "";
  el("formTitle").textContent = "＋ New Task";
  el("submitBtn").textContent = "Add Task";
  el("cancelEditBtn").style.display = "none";
}

el("taskForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const payload = {
    title: el("title").value.trim(),
    description: el("description").value.trim(),
    due_at: el("dueAt").value,
    reminder_offset: el("reminderOffset").value,
  };
  try {
    if (editingId) {
      await api(`/api/tasks/${editingId}`, { method: "PUT", body: JSON.stringify(payload) });
    } else {
      await api("/api/tasks", { method: "POST", body: JSON.stringify(payload) });
    }
    resetForm();
    loadTasks();
  } catch (err) {
    alert(err.message);
  }
});

el("cancelEditBtn").addEventListener("click", resetForm);

document.querySelectorAll(".tab").forEach((tab) => {
  tab.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach((t) => t.classList.remove("active"));
    tab.classList.add("active");
    currentFilter = tab.dataset.filter;
    renderBoard();
  });
});

function tickClock() {
  el("liveClock").textContent = new Date().toLocaleTimeString();
}
setInterval(tickClock, 1000);
tickClock();

loadTasks();
setInterval(loadTasks, 30000);