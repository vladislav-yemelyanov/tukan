import { todosOpenApiSpec } from "./openapi.ts";
import {
  type TodoPriority,
  type TodoRecord,
  type TodoStatus,
  allocateTodoId,
  todosStore,
} from "./store.ts";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
    },
  });
}

function emptyResponse(status = 204): Response {
  return new Response(null, {
    status,
    headers: CORS_HEADERS,
  });
}

function errorResponse(
  status: number,
  code: string,
  message: string,
  details?: string,
): Response {
  const payload = details === undefined ? { code, message } : { code, message, details };
  return jsonResponse(payload, status);
}

function validationError(fieldErrors: Record<string, string>): Response {
  return jsonResponse(
    {
      code: "validation_error",
      message: "One or more request fields failed validation.",
      fieldErrors,
    },
    400,
  );
}

async function readJsonBody(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const parsed = (await request.json()) as unknown;
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      return null;
    }
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}

function isTodoStatus(value: unknown): value is TodoStatus {
  return value === "todo" || value === "in_progress" || value === "done";
}

function isTodoPriority(value: unknown): value is TodoPriority {
  return value === "low" || value === "medium" || value === "high";
}

function parsePositiveInt(raw: string | null, fallback: number): number {
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 1) return fallback;
  return parsed;
}

function handleListTodos(url: URL): Response {
  const statusFilter = url.searchParams.get("status");
  const priorityFilter = url.searchParams.get("priority");
  const search = url.searchParams.get("search")?.trim().toLowerCase() ?? "";
  const page = parsePositiveInt(url.searchParams.get("page"), 1);
  const pageSize = Math.min(parsePositiveInt(url.searchParams.get("pageSize"), 25), 100);

  const filtered = todosStore.filter((todo) => {
    if (statusFilter && todo.status !== statusFilter) return false;
    if (priorityFilter && todo.priority !== priorityFilter) return false;
    if (search.length > 0) {
      const haystack = `${todo.title} ${todo.description ?? ""}`.toLowerCase();
      if (!haystack.includes(search)) return false;
    }
    return true;
  });

  const start = (page - 1) * pageSize;
  const items = filtered.slice(start, start + pageSize);

  return jsonResponse({
    items,
    total: filtered.length,
    page,
    pageSize,
  });
}

async function handleCreateTodo(request: Request): Promise<Response> {
  const body = await readJsonBody(request);
  if (!body) {
    return validationError({ body: "Expected a JSON object body." });
  }

  const fieldErrors: Record<string, string> = {};
  const title = typeof body.title === "string" ? body.title.trim() : "";
  if (title.length < 3) {
    fieldErrors.title = "Title must be at least 3 characters.";
  }

  let priority: TodoPriority = "medium";
  if (body.priority !== undefined) {
    if (!isTodoPriority(body.priority)) {
      fieldErrors.priority = "Priority must be low, medium, or high.";
    } else {
      priority = body.priority;
    }
  }

  let description: string | undefined;
  if (body.description !== undefined) {
    if (typeof body.description !== "string") {
      fieldErrors.description = "Description must be a string.";
    } else if (body.description.trim().length > 0) {
      description = body.description.trim();
    }
  }

  if (Object.keys(fieldErrors).length > 0) {
    return validationError(fieldErrors);
  }

  const now = new Date().toISOString();
  const created: TodoRecord = {
    id: allocateTodoId(),
    title,
    ...(description !== undefined ? { description } : {}),
    status: "todo",
    priority,
    createdAt: now,
    updatedAt: now,
  };
  todosStore.unshift(created);

  return jsonResponse(created, 201);
}

async function handleUpdateTodo(request: Request, todoId: string): Promise<Response> {
  const index = todosStore.findIndex((item) => item.id === todoId);
  if (index === -1) {
    return errorResponse(404, "todo_not_found", `Todo "${todoId}" was not found.`);
  }

  const body = await readJsonBody(request);
  if (!body) {
    return validationError({ body: "Expected a JSON object body." });
  }

  const current = todosStore[index]!;
  const fieldErrors: Record<string, string> = {};

  let nextTitle = current.title;
  if (body.title !== undefined) {
    if (typeof body.title !== "string" || body.title.trim().length < 3) {
      fieldErrors.title = "Title must be at least 3 characters.";
    } else {
      nextTitle = body.title.trim();
    }
  }

  let nextStatus = current.status;
  if (body.status !== undefined) {
    if (!isTodoStatus(body.status)) {
      fieldErrors.status = "Status must be todo, in_progress, or done.";
    } else {
      nextStatus = body.status;
    }
  }

  let nextPriority = current.priority;
  if (body.priority !== undefined) {
    if (!isTodoPriority(body.priority)) {
      fieldErrors.priority = "Priority must be low, medium, or high.";
    } else {
      nextPriority = body.priority;
    }
  }

  let nextDescription = current.description;
  if (body.description !== undefined) {
    if (typeof body.description !== "string") {
      fieldErrors.description = "Description must be a string.";
    } else {
      nextDescription = body.description.trim();
    }
  }

  if (Object.keys(fieldErrors).length > 0) {
    return validationError(fieldErrors);
  }

  const updated: TodoRecord = {
    ...current,
    title: nextTitle,
    status: nextStatus,
    priority: nextPriority,
    ...(nextDescription !== undefined && nextDescription.length > 0
      ? { description: nextDescription }
      : {}),
    updatedAt: new Date().toISOString(),
  };
  todosStore[index] = updated;

  return jsonResponse(updated, 200);
}

export async function handleRequest(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return emptyResponse(204);
  }

  const url = new URL(request.url);
  const path = url.pathname;
  const method = request.method.toUpperCase();

  if (method === "GET" && path === "/") {
    return jsonResponse({
      service: "tukan-examples-backend",
      specs: {
        todos: "/openapi/todos.json",
      },
    });
  }

  if (method === "GET" && path === "/openapi/todos.json") {
    return jsonResponse(todosOpenApiSpec);
  }

  if (path === "/api/v1/todos") {
    if (method === "GET") return handleListTodos(url);
    if (method === "POST") return handleCreateTodo(request);
  }

  if (path.startsWith("/api/v1/todos/")) {
    const todoId = decodeURIComponent(path.slice("/api/v1/todos/".length));
    if (!todoId || todoId.includes("/")) {
      return errorResponse(404, "not_found", `Route ${method} ${path} not found.`);
    }

    if (method === "GET") {
      const todo = todosStore.find((item) => item.id === todoId);
      if (!todo) {
        return errorResponse(404, "todo_not_found", `Todo "${todoId}" was not found.`);
      }
      return jsonResponse(todo);
    }

    if (method === "PATCH") {
      return handleUpdateTodo(request, todoId);
    }

    if (method === "DELETE") {
      const index = todosStore.findIndex((item) => item.id === todoId);
      if (index === -1) {
        return errorResponse(404, "todo_not_found", `Todo "${todoId}" was not found.`);
      }
      todosStore.splice(index, 1);
      return emptyResponse(204);
    }
  }

  return errorResponse(404, "not_found", `Route ${method} ${path} not found.`);
}

if (import.meta.main) {
  const port = Number.parseInt(process.env.PORT ?? "4000", 10);
  const server = Bun.serve({
    port,
    fetch: handleRequest,
  });

  console.log(`Tukan demo backend listening on http://localhost:${server.port}`);
  console.log(`Todos OpenAPI: http://localhost:${server.port}/openapi/todos.json`);
}
