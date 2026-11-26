export const todosOpenApiSpec = {
  openapi: "3.0.3",
  info: {
    title: "Tukan Example Todos API",
    version: "1.0.0",
    description: "Auth-free Todos CRUD API for multi-client Tukan examples.",
  },
  servers: [{ url: "http://localhost:4000" }],
  paths: {
    "/api/v1/todos": {
      get: {
        operationId: "listTodos",
        summary: "List todos with optional filtering and pagination",
        parameters: [
          {
            name: "status",
            in: "query",
            required: false,
            schema: { $ref: "#/components/schemas/TodoStatus" },
          },
          {
            name: "priority",
            in: "query",
            required: false,
            schema: { $ref: "#/components/schemas/TodoPriority" },
          },
          {
            name: "search",
            in: "query",
            required: false,
            schema: { type: "string" },
          },
          {
            name: "page",
            in: "query",
            required: false,
            schema: { type: "integer", minimum: 1 },
          },
          {
            name: "pageSize",
            in: "query",
            required: false,
            schema: { type: "integer", minimum: 1, maximum: 100 },
          },
        ],
        responses: {
          "200": {
            description: "Paginated todo list",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/TodoListResponse" },
              },
            },
          },
        },
      },
      post: {
        operationId: "createTodo",
        summary: "Create a new todo",
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/CreateTodoRequest" },
            },
          },
        },
        responses: {
          "201": {
            description: "Created todo",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/Todo" },
              },
            },
          },
          "400": {
            description: "Validation failed",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/ValidationErrorResponse" },
              },
            },
          },
        },
      },
    },
    "/api/v1/todos/{todoId}": {
      get: {
        operationId: "getTodo",
        summary: "Get a single todo by ID",
        parameters: [
          {
            name: "todoId",
            in: "path",
            required: true,
            schema: { type: "string" },
          },
        ],
        responses: {
          "200": {
            description: "Todo details",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/Todo" },
              },
            },
          },
          "404": {
            description: "Todo not found",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/ApiErrorResponse" },
              },
            },
          },
        },
      },
      patch: {
        operationId: "updateTodo",
        summary: "Update todo fields",
        parameters: [
          {
            name: "todoId",
            in: "path",
            required: true,
            schema: { type: "string" },
          },
        ],
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/UpdateTodoRequest" },
            },
          },
        },
        responses: {
          "200": {
            description: "Updated todo",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/Todo" },
              },
            },
          },
          "400": {
            description: "Validation failed",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/ValidationErrorResponse" },
              },
            },
          },
          "404": {
            description: "Todo not found",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/ApiErrorResponse" },
              },
            },
          },
        },
      },
      delete: {
        operationId: "deleteTodo",
        summary: "Delete a todo",
        parameters: [
          {
            name: "todoId",
            in: "path",
            required: true,
            schema: { type: "string" },
          },
        ],
        responses: {
          "204": {
            description: "Todo deleted",
          },
          "404": {
            description: "Todo not found",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/ApiErrorResponse" },
              },
            },
          },
        },
      },
    },
  },
  components: {
    schemas: {
      TodoStatus: {
        type: "string",
        enum: ["todo", "in_progress", "done"],
      },
      TodoPriority: {
        type: "string",
        enum: ["low", "medium", "high"],
      },
      Todo: {
        type: "object",
        required: [
          "id",
          "title",
          "status",
          "priority",
          "createdAt",
          "updatedAt",
        ],
        additionalProperties: false,
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          description: { type: "string" },
          status: { $ref: "#/components/schemas/TodoStatus" },
          priority: { $ref: "#/components/schemas/TodoPriority" },
          createdAt: { type: "string", format: "date-time" },
          updatedAt: { type: "string", format: "date-time" },
        },
      },
      TodoListResponse: {
        type: "object",
        required: ["items", "total", "page", "pageSize"],
        additionalProperties: false,
        properties: {
          items: {
            type: "array",
            items: { $ref: "#/components/schemas/Todo" },
          },
          total: { type: "integer" },
          page: { type: "integer" },
          pageSize: { type: "integer" },
        },
      },
      CreateTodoRequest: {
        type: "object",
        required: ["title"],
        additionalProperties: false,
        properties: {
          title: { type: "string", minLength: 3 },
          description: { type: "string" },
          priority: { $ref: "#/components/schemas/TodoPriority" },
        },
      },
      UpdateTodoRequest: {
        type: "object",
        additionalProperties: false,
        properties: {
          title: { type: "string", minLength: 3 },
          description: { type: "string" },
          status: { $ref: "#/components/schemas/TodoStatus" },
          priority: { $ref: "#/components/schemas/TodoPriority" },
        },
      },
      ApiErrorResponse: {
        type: "object",
        required: ["code", "message"],
        additionalProperties: false,
        properties: {
          code: { type: "string" },
          message: { type: "string" },
          details: { type: "string" },
        },
      },
      ValidationErrorResponse: {
        type: "object",
        required: ["code", "message", "fieldErrors"],
        additionalProperties: false,
        properties: {
          code: { type: "string" },
          message: { type: "string" },
          fieldErrors: {
            type: "object",
            additionalProperties: { type: "string" },
          },
        },
      },
    },
  },
} as const;
