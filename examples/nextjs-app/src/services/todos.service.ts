import { createClient, type Client, type ExtractOperations } from "tukan";

import type { Schemas as TodosSchemas } from "@/generated/todos";

export type TodosClient = Client<ExtractOperations<TodosSchemas>>;

export function createTodosService(client: TodosClient) {
  const todosPath = client.path("/api/v1/todos");
  type ListQuery = NonNullable<Parameters<typeof todosPath.get>[0]>["query"];

  return {
    client,

    list(query?: ListQuery) {
      return todosPath.get(query ? { query } : undefined);
    },

    getById(todoId: string) {
      return client.path("/api/v1/todos/{todoId}").get({
        path: { todoId },
      });
    },

    create(payload: TodosSchemas["CreateTodoRequest"]) {
      return todosPath.post({
        body: payload,
      });
    },

    update(todoId: string, payload: TodosSchemas["UpdateTodoRequest"]) {
      return client.path("/api/v1/todos/{todoId}").patch({
        path: { todoId },
        body: payload,
      });
    },

    remove(todoId: string) {
      return client.path("/api/v1/todos/{todoId}").delete({
        path: { todoId },
      });
    },
  };
}

export function createTodosClient(config: Parameters<typeof createClient>[0]): TodosClient {
  return createClient<TodosSchemas>(config);
}
