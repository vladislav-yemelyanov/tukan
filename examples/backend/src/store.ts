export type TodoStatus = "todo" | "in_progress" | "done";
export type TodoPriority = "low" | "medium" | "high";

export interface TodoRecord {
  id: string;
  title: string;
  description?: string;
  status: TodoStatus;
  priority: TodoPriority;
  createdAt: string;
  updatedAt: string;
}

const INITIAL_TODOS: readonly TodoRecord[] = [
  {
    id: "todo_01",
    title: "Generate TypeScript and Dart models with Tukan",
    description: "Run bash examples/generate.sh against /openapi/todos.json.",
    status: "done",
    priority: "high",
    createdAt: "2026-11-20T09:00:00.000Z",
    updatedAt: "2026-11-20T10:30:00.000Z",
  },
  {
    id: "todo_02",
    title: "Filter todos by status, priority, or search text",
    description: "Verify query parameters serialize cleanly in both TypeScript and Dart.",
    status: "in_progress",
    priority: "high",
    createdAt: "2026-11-21T11:15:00.000Z",
    updatedAt: "2026-11-21T12:00:00.000Z",
  },
  {
    id: "todo_03",
    title: "Inspect typed 400 validation errors in UI",
    description: "Submit a short todo title (< 3 chars) and render fieldErrors.",
    status: "todo",
    priority: "medium",
    createdAt: "2026-11-23T14:20:00.000Z",
    updatedAt: "2026-11-23T14:20:00.000Z",
  },
  {
    id: "todo_04",
    title: "Cycle todo status and inspect item details",
    description: "Send partial PATCH updates and GET /api/v1/todos/{todoId}.",
    status: "todo",
    priority: "low",
    createdAt: "2026-11-24T07:05:00.000Z",
    updatedAt: "2026-11-24T07:45:00.000Z",
  },
];

export const todosStore: TodoRecord[] = INITIAL_TODOS.map((todo) => ({ ...todo }));

let nextTodoCounter = INITIAL_TODOS.length + 1;

export function allocateTodoId(): string {
  const id = `todo_${String(nextTodoCounter).padStart(2, "0")}`;
  nextTodoCounter += 1;
  return id;
}
