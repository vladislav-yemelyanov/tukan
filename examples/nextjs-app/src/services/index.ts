import { createClientConfig, type ClientRuntimeOptions } from "./config";
import { createTodosClient, createTodosService } from "./todos.service";

export type { Schemas as TodosSchemas } from "@/generated/todos";

export function createServices(runtime: ClientRuntimeOptions = {}) {
  const todosClient = createTodosClient(createClientConfig(runtime));
  const todos = createTodosService(todosClient);

  return {
    todos,
  } as const;
}

export const services = createServices();
