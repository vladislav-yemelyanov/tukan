"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";

import { services, type TodosSchemas } from "@/services";

type Todo = TodosSchemas["Todo"];
type TodoStatus = TodosSchemas["TodoStatus"];
type TodoPriority = TodosSchemas["TodoPriority"];

const NEXT_STATUS: Record<TodoStatus, TodoStatus> = {
  todo: "in_progress",
  in_progress: "done",
  done: "todo",
};

export default function HomePage() {
  const [statusFilter, setStatusFilter] = useState<"" | TodoStatus>("");
  const [priorityFilter, setPriorityFilter] = useState<"" | TodoPriority>("");
  const [search, setSearch] = useState("");
  const [todos, setTodos] = useState<Todo[]>([]);
  const [totalTodos, setTotalTodos] = useState(0);
  const [selectedTodo, setSelectedTodo] = useState<Todo | null>(null);
  const [notice, setNotice] = useState<{
    kind: "ok" | "err";
    text: string;
  } | null>(null);
  const [busy, setBusy] = useState(false);

  const [newTitle, setNewTitle] = useState("");
  const [newDescription, setNewDescription] = useState("");
  const [newPriority, setNewPriority] = useState<TodoPriority>("medium");
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});

  const loadTodos = useCallback(async () => {
    setBusy(true);

    const { data, error } = await services.todos.list({
      status: statusFilter || undefined,
      priority: priorityFilter || undefined,
      search: search.trim() || undefined,
    });

    setBusy(false);

    if (error) {
      setNotice({ kind: "err", text: error.message });
      setTodos([]);
      setTotalTodos(0);
      return;
    }

    setTodos(data.items);
    setTotalTodos(data.total);
  }, [priorityFilter, search, statusFilter]);

  useEffect(() => {
    void loadTodos();
  }, [loadTodos]);

  async function handleInspectTodo(todoId: string) {
    const { data, error } = await services.todos.getById(todoId);
    if (error) {
      setNotice({
        kind: "err",
        text: error.body?.message ?? error.message,
      });
      return;
    }

    setSelectedTodo(data);
  }

  async function handleCreateTodo(event: FormEvent) {
    event.preventDefault();
    setFieldErrors({});
    setNotice(null);

    const trimmedDescription = newDescription.trim();
    const { data, error } = await services.todos.create({
      title: newTitle,
      ...(trimmedDescription.length > 0 ? { description: trimmedDescription } : {}),
      priority: newPriority,
    });

    if (error) {
      if (error.is(400) && error.body) {
        setFieldErrors(error.body.fieldErrors);
        setNotice({ kind: "err", text: error.body.message });
        return;
      }

      setNotice({ kind: "err", text: error.message });
      return;
    }

    setNewTitle("");
    setNewDescription("");
    setSelectedTodo(data);
    setNotice({ kind: "ok", text: `Created todo ${data.id}: ${data.title}` });
    await loadTodos();
  }

  async function handleCycleStatus(todo: Todo) {
    const { data, error } = await services.todos.update(todo.id, {
      status: NEXT_STATUS[todo.status],
    });

    if (error) {
      setNotice({
        kind: "err",
        text: error.is(400) || error.is(404) ? (error.body?.message ?? error.message) : error.message,
      });
      return;
    }

    if (selectedTodo?.id === data.id) {
      setSelectedTodo(data);
    }
    await loadTodos();
  }

  async function handleDeleteTodo(todoId: string) {
    const { error } = await services.todos.remove(todoId);
    if (error) {
      setNotice({
        kind: "err",
        text: error.body?.message ?? error.message,
      });
      return;
    }

    if (selectedTodo?.id === todoId) {
      setSelectedTodo(null);
    }
    await loadTodos();
  }

  return (
    <main className="page">
      <header className="header">
        <div>
          <h1>Tukan + Next.js Todo Example</h1>
          <p className="muted">
            Typed OpenAPI models + <span className="mono">tukan</span> wrapped inside{" "}
            <span className="mono">src/services</span>.
          </p>
        </div>
      </header>

      <section className="card">
        <div className="row" style={{ justifyContent: "space-between", marginBottom: 12 }}>
          <div>
            <h2>Todos ({totalTodos})</h2>
            <p className="muted">
              Leave title &lt; 3 chars to inspect typed <span className="mono">400</span> validation errors.
            </p>
          </div>
          <button type="button" disabled={busy} onClick={() => void loadTodos()}>
            Reload List
          </button>
        </div>

        <form onSubmit={handleCreateTodo} className="row" style={{ marginBottom: 14 }}>
          <input
            aria-label="New todo title"
            placeholder="New todo title (min 3 chars)"
            value={newTitle}
            onChange={(e) => setNewTitle(e.target.value)}
            style={{ flex: "2 1 220px" }}
          />
          <input
            aria-label="New todo description"
            placeholder="Description (optional)"
            value={newDescription}
            onChange={(e) => setNewDescription(e.target.value)}
            style={{ flex: "2 1 220px" }}
          />
          <select
            aria-label="New todo priority"
            value={newPriority}
            onChange={(e) => setNewPriority(e.target.value as TodoPriority)}
            style={{ flex: "0 0 130px" }}
          >
            <option value="low">low</option>
            <option value="medium">medium</option>
            <option value="high">high</option>
          </select>
          <button type="submit" className="primary">
            Create Todo
          </button>
        </form>

        {Object.keys(fieldErrors).length > 0 && (
          <div className="banner err" style={{ marginBottom: 12 }}>
            {Object.entries(fieldErrors)
              .map(([field, msg]) => `${field}: ${msg}`)
              .join("\n")}
          </div>
        )}

        <div className="row">
          <input
            aria-label="Search todos"
            placeholder="Search todos..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ flex: "2 1 200px" }}
          />
          <select
            aria-label="Filter status"
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value as "" | TodoStatus)}
            style={{ flex: "1 1 150px" }}
          >
            <option value="">All statuses</option>
            <option value="todo">todo</option>
            <option value="in_progress">in_progress</option>
            <option value="done">done</option>
          </select>
          <select
            aria-label="Filter priority"
            value={priorityFilter}
            onChange={(e) => setPriorityFilter(e.target.value as "" | TodoPriority)}
            style={{ flex: "1 1 150px" }}
          >
            <option value="">All priorities</option>
            <option value="low">low</option>
            <option value="medium">medium</option>
            <option value="high">high</option>
          </select>
        </div>

        {notice && <div className={`banner ${notice.kind}`}>{notice.text}</div>}

        {selectedTodo && (
          <div className="banner ok" style={{ marginTop: 12 }}>
            <strong>
              Selected Todo ({selectedTodo.id}): {selectedTodo.title}
            </strong>
            {"\n"}
            status={selectedTodo.status} | priority={selectedTodo.priority}
            {selectedTodo.description ? `\n${selectedTodo.description}` : ""}
          </div>
        )}

        <div className="task-list">
          {todos.map((todo) => (
            <div key={todo.id} className="task-item">
              <div className="task-top">
                <div>
                  <strong>{todo.title}</strong>
                  {todo.description && <p className="muted">{todo.description}</p>}
                </div>
                <div className="row">
                  <span className="badge">{todo.status}</span>
                  <span className="badge">{todo.priority}</span>
                </div>
              </div>
              <div className="row" style={{ justifyContent: "space-between" }}>
                <span className="muted mono">
                  {todo.id} • updated {new Date(todo.updatedAt).toLocaleString()}
                </span>
                <div className="row">
                  <button type="button" onClick={() => void handleInspectTodo(todo.id)}>
                    Inspect (GET byId)
                  </button>
                  <button type="button" onClick={() => void handleCycleStatus(todo)}>
                    Next Status → {NEXT_STATUS[todo.status]}
                  </button>
                  <button
                    type="button"
                    className="danger"
                    onClick={() => void handleDeleteTodo(todo.id)}
                  >
                    Delete
                  </button>
                </div>
              </div>
            </div>
          ))}
          {todos.length === 0 && !busy && (
            <p className="muted" style={{ marginTop: 8 }}>
              No todos loaded.
            </p>
          )}
        </div>
      </section>
    </main>
  );
}
