// Generated from OpenAPI schemas; defaults not applied.
export interface Schemas {
  "ApiErrorResponse": {
    "code": string;
    "details"?: string;
    "message": string;
  };
  "CreateTodoRequest": {
    "description"?: string;
    "priority"?: Schemas["TodoPriority"];
    /**
     * minLength: 3
     */
    "title": string;
  };
  "Todo": {
    "createdAt": string;
    "description"?: string;
    "id": string;
    "priority": Schemas["TodoPriority"];
    "status": Schemas["TodoStatus"];
    "title": string;
    "updatedAt": string;
  };
  "TodoListResponse": {
    "items": Schemas["Todo"][];
    "page": number;
    "pageSize": number;
    "total": number;
  };
  "TodoPriority": "low" | "medium" | "high";
  "TodoStatus": "todo" | "in_progress" | "done";
  "UpdateTodoRequest": {
    "description"?: string;
    "priority"?: Schemas["TodoPriority"];
    "status"?: Schemas["TodoStatus"];
    /**
     * minLength: 3
     */
    "title"?: string;
  };
  "ValidationErrorResponse": {
    "code": string;
    "fieldErrors": {
      [key: string]: string;
    };
    "message": string;
  };
  "Operations": {
    "/api/v1/todos": {
      /**
       * GET /api/v1/todos
       * List todos with optional filtering and pagination
       */
      "get": {
        "parameters": {
          "query"?: {
            /**
             * minimum: 1
             */
            "page"?: number;
            /**
             * maximum: 100
             * minimum: 1
             */
            "pageSize"?: number;
            "priority"?: Schemas["TodoPriority"];
            "search"?: string;
            "status"?: Schemas["TodoStatus"];
          };
        };
        "responses": {
          "200": {
            "application/json": Schemas["TodoListResponse"];
          };
        };
      };
      /**
       * POST /api/v1/todos
       * Create a new todo
       */
      "post": {
        "parameters": {};
        "requestBody": {
          /**
           * Request body: required. Content type: application/json.
           */
          "application/json": Schemas["CreateTodoRequest"];
        };
        "responses": {
          "201": {
            "application/json": Schemas["Todo"];
          };
          "400": {
            "application/json": Schemas["ValidationErrorResponse"];
          };
        };
      };
    };
    "/api/v1/todos/{todoId}": {
      /**
       * DELETE /api/v1/todos/{todoId}
       * Delete a todo
       */
      "delete": {
        "parameters": {
          "path": {
            "todoId": string;
          };
        };
        "responses": {
          "204": {};
          "404": {
            "application/json": Schemas["ApiErrorResponse"];
          };
        };
      };
      /**
       * GET /api/v1/todos/{todoId}
       * Get a single todo by ID
       */
      "get": {
        "parameters": {
          "path": {
            "todoId": string;
          };
        };
        "responses": {
          "200": {
            "application/json": Schemas["Todo"];
          };
          "404": {
            "application/json": Schemas["ApiErrorResponse"];
          };
        };
      };
      /**
       * PATCH /api/v1/todos/{todoId}
       * Update todo fields
       */
      "patch": {
        "parameters": {
          "path": {
            "todoId": string;
          };
        };
        "requestBody": {
          /**
           * Request body: required. Content type: application/json.
           */
          "application/json": Schemas["UpdateTodoRequest"];
        };
        "responses": {
          "200": {
            "application/json": Schemas["Todo"];
          };
          "400": {
            "application/json": Schemas["ValidationErrorResponse"];
          };
          "404": {
            "application/json": Schemas["ApiErrorResponse"];
          };
        };
      };
    };
  };
}
