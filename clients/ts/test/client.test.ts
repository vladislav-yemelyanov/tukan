import {
  ApiError,
  ApiResponseError,
  CancelledError,
  DecodeError,
  NetworkError,
  TimeoutError,
  UnexpectedClientError,
  UnexpectedHttpError,
  createClient,
  type RequestContext,
} from "../src/index.js";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(`Assertion failed: ${message}`);
  }
}

function assertEqual<T>(actual: T, expected: T, label: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`);
  }
}

function assertDeepEqual(actual: unknown, expected: unknown, label: string): void {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`${label}: expected ${expectedJson}, got ${actualJson}`);
  }
}

interface SyntheticSchemas {
  User: {
    id: string;
    name: string;
  };
  ProblemDetails: {
    title?: string | null;
    detail?: string | null;
    status?: number | null;
  };
  VersionInfo: {
    version?: string;
    uptime?: string;
  };
  TransactionCost: {
    costFixed?: number | null;
    subtype?: "card" | "transfer";
  };
  Operations: {
    "/versions": {
      get: {
        parameters: {};
        responses: {
          "200": { "application/json": SyntheticSchemas["VersionInfo"] };
        };
      };
    };
    "/possible-number": {
      get: {
        parameters: {};
        responses: {
          "200": { "application/json": string };
        };
      };
    };
    "/cost": {
      get: {
        parameters: {
          query: {
            externalBankAccountId: string;
            filter?: { min?: number; max?: number } | null;
            since?: string | null;
          };
        };
        responses: {
          "200": { "application/json": SyntheticSchemas["TransactionCost"] };
          "400": { "application/problem+json": SyntheticSchemas["ProblemDetails"] };
          "401": {};
          "403": {};
        };
      };
      post: {
        parameters: {};
        requestBody: {
          "application/json": { costFixed: number };
        };
        responses: {
          "200": {};
          "400": { "application/problem+json": SyntheticSchemas["ProblemDetails"] };
        };
      };
      delete: {
        parameters: {};
        requestBody: {
          "application/json": { accountId: string };
        };
        responses: {
          "200": {};
        };
      };
    };
    "/users/{id}": {
      get: {
        parameters: {
          path: { id: string };
          query?: {
            expand?: boolean | null;
            tags?: (string | null)[] | null;
            limit?: number | null;
          };
          header: {
            "X-Request-Id": string;
            "X-Trace"?: string | null;
            "X-Count"?: number;
          };
          cookie?: {
            session?: string | null;
          };
        };
        responses: {
          "200": { "application/json": SyntheticSchemas["User"] };
          "204": {};
          "400": { "application/problem+json": SyntheticSchemas["ProblemDetails"] };
          "401": {};
        };
      };
      head: {
        parameters: {
          path: { id: string };
        };
        responses: {
          "200": {};
          "404": {};
        };
      };
      put: {
        parameters: {
          path: { id: string };
        };
        requestBody: {
          "application/json": { name: string };
        };
        responses: {
          "200": { "application/json": SyntheticSchemas["User"] };
        };
      };
    };
    "/optional-headers": {
      get: {
        parameters: {
          header?: {
            "X-Optional"?: string;
          };
        };
        responses: {
          "200": { "application/json": { ok: boolean } };
        };
      };
    };
    "/upload-only": {
      post: {
        parameters: {};
        requestBody: {
          "multipart/form-data": {
            file: Blob;
            note?: string | null;
            tags?: (string | null)[] | null;
          };
        };
        responses: {
          "201": { "application/json": { id: string } };
        };
      };
    };
    "/optional-upload": {
      post: {
        parameters: {};
        requestBody?: {
          "multipart/form-data": {
            file: Blob;
          };
        };
        responses: {
          "204": {};
        };
      };
    };
    "/mixed-body": {
      post: {
        parameters: {};
        requestBody: {
          "application/json": { jsonOnly: string };
          "multipart/form-data": { file: Blob };
          "text/plain": string;
        };
        responses: {
          "200": { "application/json": { ok: boolean } };
        };
      };
    };
    "/login": {
      post: {
        parameters: {};
        requestBody: {
          "application/x-www-form-urlencoded": {
            username: string;
            password: string;
          };
        };
        responses: {
          "200": { "application/json": { token: string } };
        };
      };
    };
    "/no-declared-errors": {
      get: {
        parameters: {};
        responses: {
          "200": { "application/json": { ok: boolean } };
        };
      };
    };
    "/orders": {
      post: {
        parameters: {};
        requestBody: {
          "application/json": { item: string };
        };
        responses: {
          "201": { "application/json": { orderId: string } };
          "400": { "application/json": { fields: Record<string, string> } };
          "401": {};
          "409": { "application/json": { conflictId: string } };
        };
      };
    };
    "/default-error": {
      get: {
        parameters: {};
        responses: {
          "200": { "application/json": { ok: boolean } };
          "default": { "application/json": { code: string } };
        };
      };
    };
    "/files-multi": {
      post: {
        parameters: {};
        requestBody: {
          "multipart/form-data": {
            primary: File;
            attachments: Blob[];
            count: number;
            active: boolean;
            meta: { source: string };
          };
        };
        responses: {
          "201": { "application/json": { received: number } };
        };
      };
    };
    "/binary-upload": {
      post: {
        parameters: {};
        requestBody: {
          "application/octet-stream": Uint8Array;
        };
        responses: {
          "200": { "application/json": { size: number } };
        };
      };
    };
    "/export.bin": {
      get: {
        parameters: {};
        responses: {
          "200": { "application/octet-stream": Blob };
        };
      };
    };
    "/export.csv": {
      get: {
        parameters: {};
        responses: {
          "200": { "text/csv": string };
        };
      };
    };
    "/retryable": {
      get: {
        parameters: {};
        responses: {
          "200": { "application/json": { ok: boolean } };
          "503": { "application/json": { code: string } };
        };
      };
    };
  };
}

interface CollisionSchemas {
  Operations: string;
  Operations_: {
    "/ping": {
      get: {
        parameters: {};
        responses: {
          "200": { "application/json": string };
        };
      };
    };
  };
}

// Compile-time type checks (verified by tsc, never executed at runtime).
async function compileTimeChecks() {
  const synthetic = createClient<SyntheticSchemas>({
    baseUrl: "https://example.test",
    headers: async ({ method, path }) => ({
      Authorization: "Bearer dynamic",
      "X-Method": method,
      "X-Path": path,
    }),
    requestInit: { credentials: "include" },
    timeoutMs: 5000,
    onRequest: (ctx) => {
      ctx.headers.set("X-Hook", "1");
    },
    onResponse: (_ctx, res) => res,
    onError: (_ctx, err) => {
      void err.message;
    },
  });
  const collision = createClient<CollisionSchemas["Operations_"]>({
    baseUrl: "https://example.test",
  });

  // 0-argument endpoints and void narrowing.
  const versionRes = await synthetic.path("/versions").get();
  if (versionRes.error) {
    const _rawErr: unknown = versionRes.error.body;
    void _rawErr;
    return;
  }
  const _uptime: string | undefined = versionRes.data.uptime;
  const _versionHttpStatus: number = versionRes.response.status;
  void _uptime;
  void _versionHttpStatus;

  // Declared 400 ProblemDetails response narrows `error.body`.
  const costRes = await synthetic.path("/cost").get({
    query: { externalBankAccountId: "acc-1" },
  });
  if (costRes.error) {
    const _detail: string | null | undefined = costRes.error.body?.detail;
    void _detail;
    return;
  }
  const _costFixed: number | null | undefined = costRes.data.costFixed;
  const _costStatus: number = costRes.response.status;
  void _costFixed;
  void _costStatus;

  // Primitive string response narrowing.
  const numberRes = await synthetic.path("/possible-number").get();
  if (numberRes.error) return;
  const _possibleNumber: string = numberRes.data;
  void _possibleNumber;

  // Void POST (no 2xx schema in spec) still narrows data cleanly.
  const voidRes = await synthetic.path("/cost").post({
    body: { costFixed: 1 },
  });
  if (voidRes.error) return;
  const _voidData: undefined = voidRes.data;
  void _voidData;

  // Destructured `if (error)` narrows `data`, `error`, and `response`.
  const { data: dData, error: dError, response: dResponse } = await synthetic
    .path("/cost")
    .get({ query: { externalBankAccountId: "acc-1" } });
  if (dError) {
    const _errDetail: string | null | undefined = dError.body?.detail;
    const _errStatus: number | undefined = dError.status;
    void _errDetail;
    void _errStatus;
    return;
  }
  const _dSubtype: "card" | "transfer" | undefined = dData.subtype;
  const _dStatus: number = dResponse.status;
  void _dSubtype;
  void _dStatus;

  // Extra headers (Authorization, Accept, etc.) allowed alongside required OpenAPI header params.
  const userRes = await synthetic.path("/users/{id}").get({
    path: { id: "u-1" },
    headers: {
      "X-Request-Id": "req-1",
      Authorization: "Bearer token",
      Accept: "application/json",
    },
    timeoutMs: 1000,
    requestInit: { cache: "no-store" },
  });
  if (userRes.error) {
    const _title: string | null | undefined = userRes.error.body?.title;
    void _title;
    return;
  }
  const _maybeUser: SyntheticSchemas["User"] | undefined = userRes.data;
  void _maybeUser;

  // Optional query/header/cookie properties accept explicit `undefined` under exactOptionalPropertyTypes.
  const userWithUndefinedRes = await synthetic.path("/users/{id}").get({
    path: { id: "u-1" },
    query: { expand: undefined, limit: undefined },
    headers: {
      "X-Request-Id": "req-1",
      "X-Count": undefined,
    },
    cookie: { session: undefined },
    extra: { attempt: 1 },
  });
  void userWithUndefinedRes;

  // Exhaustive discriminated narrowing across all 7 ClientError variants.
  const exhaustiveRes = await synthetic.path("/orders").post({ body: { item: "book" } });
  if (exhaustiveRes.error) {
    const err = exhaustiveRes.error;
    switch (err.kind) {
      case "response": {
        const _s: number = err.status;
        const _r: Response = err.response;
        void _s;
        void _r;
        break;
      }
      case "unexpected_http": {
        const _s: number = err.status;
        const _raw: unknown = err.rawBody;
        void _s;
        void _raw;
        break;
      }
      case "network": {
        const _s: undefined = err.status;
        void _s;
        break;
      }
      case "timeout": {
        const _ms: number | undefined = err.timeoutMs;
        void _ms;
        break;
      }
      case "cancelled": {
        const _reason: unknown = err.reason;
        void _reason;
        break;
      }
      case "decode": {
        const _s: number = err.status;
        const _raw: unknown = err.rawBody;
        void _s;
        void _raw;
        break;
      }
      case "client": {
        const _stage: "request_build" | "hook" | "internal" = err.stage;
        void _stage;
        break;
      }
      default: {
        const _never: never = err;
        void _never;
      }
    }
  }

  // Optional header parameters also allow extra headers and HeadersInit.
  await synthetic.path("/optional-headers").get({
    headers: {
      "X-Optional": "yes",
      Authorization: "Bearer token",
    },
  });
  await synthetic.path("/optional-headers").get({
    headers: new Headers({ Accept: "application/json" }),
  });

  // HEAD operation with no body.
  const headRes = await synthetic.path("/users/{id}").head({ path: { id: "u-1" } });
  if (!headRes.error) {
    const _headData: undefined = headRes.data;
    void _headData;
  }

  // Endpoint with no declared error statuses falls back to `unknown` error body.
  const plainErrRes = await synthetic.path("/no-declared-errors").get();
  if (plainErrRes.error) {
    const _basePlain: ApiError = plainErrRes.error;
    const _body: unknown = plainErrRes.error.body;
    void _basePlain;
    void _body;
    return;
  }

  // `default` error response preserves typed error body.
  const defaultErrRes = await synthetic.path("/default-error").get();
  if (defaultErrRes.error) {
    const _baseDefault: ApiError = defaultErrRes.error;
    const _code: string | undefined = defaultErrRes.error.body?.code;
    void _baseDefault;
    void _code;
    return;
  }

  // `error.is(status)` narrows status, response, and per-status error body schema.
  const orderRes = await synthetic.path("/orders").post({ body: { item: "book" } });
  if (orderRes.error) {
    const base: ApiError = orderRes.error;
    if (base.status === 401) {
      const _s: 401 = base.status;
      const _b: unknown = base.body;
      void _s;
      void _b;
    }

    if (orderRes.error.is(400)) {
      const _status: 400 = orderRes.error.status;
      const _httpRes: Response = orderRes.error.response;
      const _fields: Record<string, string> | undefined = orderRes.error.body?.fields;
      // @ts-expect-error 400 body cannot have 409 `conflictId`
      const _wrong = orderRes.error.body?.conflictId;
      void _status;
      void _httpRes;
      void _fields;
      void _wrong;
    } else if (orderRes.error.is(409)) {
      const _status: 409 = orderRes.error.status;
      const _conflictId: string | undefined = orderRes.error.body?.conflictId;
      // @ts-expect-error 409 body cannot have 400 `fields`
      const _wrong = orderRes.error.body?.fields;
      void _status;
      void _conflictId;
      void _wrong;
    } else if (orderRes.error.is(401)) {
      const _status: 401 = orderRes.error.status;
      const _emptyBody: undefined = orderRes.error.body;
      void _status;
      void _emptyBody;
    }

    // @ts-expect-error undocumented status code cannot be passed to `is()`
    orderRes.error.is(418);
    return;
  }

  // Operations_ collision type passes straight through.
  const pingRes = await collision.path("/ping").get();
  if (!pingRes.error) {
    const _pong: string = pingRes.data;
    void _pong;
  }

  // Optional multipart-only body allows zero arguments.
  await synthetic.path("/optional-upload").post();

  // Negative compile-time assertions:
  // @ts-expect-error unknown endpoint path must fail
  synthetic.path("/does-not-exist");

  // @ts-expect-error PATCH is not defined on /versions
  synthetic.path("/versions").patch();

  // @ts-expect-error missing required query parameters
  await synthetic.path("/cost").get();

  // @ts-expect-error missing required query field `externalBankAccountId`
  await synthetic.path("/cost").get({ query: {} });

  // @ts-expect-error missing required requestBody on POST /cost
  await synthetic.path("/cost").post();

  // @ts-expect-error missing required path and header parameters
  await synthetic.path("/users/{id}").get({ path: { id: "1" } });

  await synthetic.path("/users/{id}").get({
    path: { id: "1" },
    // @ts-expect-error missing required OpenAPI header `X-Request-Id` even when extra headers are provided
    headers: { Authorization: "Bearer token" },
  });

  await synthetic.path("/users/{id}").get({
    path: { id: "1" },
    headers: {
      "X-Request-Id": "req-1",
      // @ts-expect-error declared header `X-Count` must be a number
      "X-Count": "not-a-number",
    },
  });

  // @ts-expect-error missing required multipart contentType
  await synthetic.path("/upload-only").post({ body: { file: new Blob([]) } });

  await synthetic.path("/mixed-body").post({
    contentType: "multipart/form-data",
    // @ts-expect-error mismatched body shape for multipart/form-data on mixed-body endpoint
    body: { jsonOnly: "wrong" },
  });
}

void compileTimeChecks;

interface CapturedCall {
  url: string;
  init: RequestInit;
}

function createMockFetch(
  handler: (call: CapturedCall) => Response | Promise<Response>,
): { fetch: typeof fetch; calls: CapturedCall[] } {
  const calls: CapturedCall[] = [];
  const mockFetch: typeof fetch = async (input, init) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    const call: CapturedCall = { url, init: init ?? {} };
    calls.push(call);
    return handler(call);
  };
  return { fetch: mockFetch, calls };
}

async function runTests(): Promise<void> {
  let passed = 0;

  // 1. URL joining (trailing slash + relative baseUrl), path encoding, query serialization.
  {
    const { fetch, calls } = createMockFetch(() =>
      new Response(JSON.stringify({ id: "1", name: "Ada" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );

    const client = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test///",
      fetch,
    });

    const { data, error, response } = await client.path("/users/{id}").get({
      path: { id: "a/b?c" },
      query: {
        expand: false,
        limit: 0,
        tags: ["one", "two"],
      },
      headers: {
        "X-Request-Id": "req-42",
      },
    });

    assert(!error, "no error");
    assertDeepEqual(data, { id: "1", name: "Ada" }, "parsed user");
    assertEqual(response.status, 200, "status 200");
    assertEqual(
      calls[0]?.url,
      "https://api.example.test/users/a%2Fb%3Fc?expand=false&limit=0&tags=one&tags=two",
      "URL with encoded path and repeated array query params",
    );

    const relMock = createMockFetch(() =>
      new Response(JSON.stringify("pong"), {
        status: 200,
        headers: { "content-type": "application/json; charset=utf-8" },
      }),
    );
    const rootClient = createClient<CollisionSchemas["Operations_"]>({
      baseUrl: "",
      fetch: relMock.fetch,
    });
    const pingRoot = await rootClient.path("/ping").get();
    assertEqual(relMock.calls[0]?.url, "/ping", "empty baseUrl yields relative path");
    assertEqual(pingRoot.data, "pong", "primitive JSON string decoded");

    const prefixMock = createMockFetch(() =>
      new Response(JSON.stringify("pong"), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
    const prefixClient = createClient<CollisionSchemas["Operations_"]>({
      baseUrl: "/proxy/",
      fetch: prefixMock.fetch,
    });
    await prefixClient.path("/ping").get();
    assertEqual(prefixMock.calls[0]?.url, "/proxy/ping", "relative prefix baseUrl strips trailing slash");
    passed++;
  }

  // 2. Undefined and null query/header/cookie/form values skipped; nested objects & Date serialized.
  {
    const { fetch, calls } = createMockFetch(() => new Response(null, { status: 204 }));
    const client = createClient<SyntheticSchemas>({ baseUrl: "https://api.example.test", fetch });

    await client.path("/users/{id}").get({
      path: { id: "42" },
      query: {
        expand: null,
        limit: 5,
        tags: ["a", null, "b"],
      },
      headers: {
        "X-Request-Id": "req-null",
        "X-Trace": null,
      },
      cookie: {
        session: null,
      },
    });

    assertEqual(
      calls[0]?.url,
      "https://api.example.test/users/42?limit=5&tags=a&tags=b",
      "null and undefined query params omitted",
    );
    const sentHeaders = calls[0]?.init.headers as Headers;
    assertEqual(sentHeaders.get("x-trace"), null, "null header omitted");
    assertEqual(sentHeaders.get("cookie"), null, "null cookie omitted");

    await client.path("/cost").get({
      query: {
        externalBankAccountId: "acc-1",
        filter: { min: 10, max: 20 },
        since: new Date("2026-01-02T03:04:05.000Z") as unknown as string,
      },
    });

    assertEqual(
      calls[1]?.url,
      "https://api.example.test/cost?externalBankAccountId=acc-1&filter=%7B%22min%22%3A10%2C%22max%22%3A20%7D&since=2026-01-02T03%3A04%3A05.000Z",
      "object and Date serialized cleanly in query params",
    );
    passed++;
  }

  // 3. Missing path parameter returns ApiError without throwing.
  {
    const { fetch } = createMockFetch(() => {
      throw new Error("fetch should not be called");
    });
    const client = createClient<SyntheticSchemas>({ baseUrl: "https://api.example.test", fetch });

    const result = await client.path("/users/{id}").get({
      path: {} as { id: string },
      headers: { "X-Request-Id": "req-missing" },
    });

    assert(result.error instanceof ApiError, "missing path param yields ApiError");
    assert(result.error instanceof UnexpectedClientError, "missing path param yields UnexpectedClientError");
    assertEqual(result.error.kind, "client", "missing path param kind");
    assertEqual(result.error.stage, "request_build", "missing path param stage");
    assertEqual(result.error.status, undefined, "no HTTP status when URL build fails");
    assertEqual(result.response, undefined, "no Response when URL build fails");
    passed++;
  }

  // 4. Base headers merge/override without mutating inputs, plus Cookie formatting and extra headers.
  {
    const baseHeaders: Record<string, string> = {
      Authorization: "Bearer base-token",
      "X-Trace": "from-base",
    };

    const { fetch, calls } = createMockFetch(() => new Response(null, { status: 204 }));
    const client = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      headers: baseHeaders,
      fetch,
    });

    await client.path("/users/{id}").get({
      path: { id: "7" },
      headers: {
        "X-Request-Id": "req-7",
        "X-Trace": "from-request",
        Accept: "application/json",
      },
      cookie: {
        session: "a b;c",
      },
    });

    const sentHeaders = calls[0]?.init.headers as Headers;
    assert(sentHeaders instanceof Headers, "headers normalized to Headers");
    assertEqual(sentHeaders.get("authorization"), "Bearer base-token", "base header preserved");
    assertEqual(sentHeaders.get("x-trace"), "from-request", "request header overrides base");
    assertEqual(sentHeaders.get("x-request-id"), "req-7", "required request header set");
    assertEqual(sentHeaders.get("accept"), "application/json", "extra per-request header set");
    assertEqual(sentHeaders.get("cookie"), "session=a%20b%3Bc", "cookie formatted");
    assertEqual(baseHeaders["X-Trace"], "from-base", "input baseHeaders not mutated");
    passed++;
  }

  // 5. JSON body serialization and DELETE with JSON body.
  {
    const { fetch, calls } = createMockFetch(() => new Response(null, { status: 200 }));
    const client = createClient<SyntheticSchemas>({ baseUrl: "https://api.example.test", fetch });

    const res = await client.path("/cost").delete({
      body: { accountId: "acc-1" },
    });

    assertEqual(res.error, undefined, "void 200 DELETE succeeds");
    assertEqual(res.data, undefined, "empty 200 body parses as undefined");
    assertEqual(calls[0]?.init.method, "DELETE", "DELETE method uppercased");
    assertEqual(calls[0]?.init.body, '{"accountId":"acc-1"}', "DELETE body serialized as JSON");
    assertEqual((calls[0]?.init.headers as Headers).get("content-type"), "application/json", "JSON Content-Type set");
    passed++;
  }

  // 6. multipart/form-data builds FormData with Blob & array fields (omitting nulls), without manual Content-Type.
  {
    const { fetch, calls } = createMockFetch(() =>
      new Response(JSON.stringify({ id: "upload-1" }), {
        status: 201,
        headers: { "Content-Type": "application/json" },
      }),
    );
    const client = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      headers: { "Content-Type": "application/json" },
      fetch,
    });

    const blob = new Blob(["hello"], { type: "text/plain" });
    const res = await client.path("/upload-only").post({
      contentType: "multipart/form-data",
      body: {
        file: blob,
        note: null,
        tags: ["alpha", null, "beta"],
      },
    });

    assertEqual(res.error, undefined, "multipart upload succeeds");
    assertDeepEqual(res.data, { id: "upload-1" }, "201 response parsed");

    const sentBody = calls[0]?.init.body;
    const sentHeaders = calls[0]?.init.headers as Headers;
    assert(sentBody instanceof FormData, "multipart body converted to FormData");
    assert(sentBody.get("file") instanceof Blob, "Blob appended directly to FormData");
    assertEqual(sentBody.get("note"), null, "null multipart field omitted");
    assertDeepEqual(sentBody.getAll("tags"), ["alpha", "beta"], "array appended without nulls");
    assertEqual(sentHeaders.get("content-type"), null, "manual Content-Type stripped so fetch adds boundary");
    passed++;
  }

  // 7. Content-Type precedence: request `contentType` overrides base Content-Type; explicit request header wins.
  {
    const { fetch, calls } = createMockFetch(() =>
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
    const client = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      headers: { "Content-Type": "application/json" },
      fetch,
    });

    await client.path("/login").post({
      contentType: "application/x-www-form-urlencoded",
      body: { username: "alice", password: "secret" },
    });

    assert(calls[0]?.init.body instanceof URLSearchParams, "body serialized as URLSearchParams");
    assertEqual(calls[0]?.init.body.toString(), "username=alice&password=secret", "urlencoded payload matches");
    assertEqual(
      (calls[0]?.init.headers as Headers).get("content-type"),
      "application/x-www-form-urlencoded",
      "explicit contentType overrides base Content-Type",
    );

    await client.path("/mixed-body").post({
      contentType: "text/plain",
      body: "hello world",
    });
    assertEqual(
      (calls[1]?.init.headers as Headers).get("content-type"),
      "text/plain",
      "text/plain contentType overrides base Content-Type",
    );
    assertEqual(calls[1]?.init.body, "hello world", "text/plain body preserved");

    await client.path("/mixed-body").post({
      contentType: "text/plain",
      headers: { "Content-Type": "text/plain; charset=utf-8" },
      body: "hello charset",
    });
    assertEqual(
      (calls[2]?.init.headers as Headers).get("content-type"),
      "text/plain; charset=utf-8",
      "per-request Content-Type header takes precedence",
    );
    passed++;
  }

  // 8. 400 application/problem+json, 401 empty body, and 502 text/html errors.
  {
    let step = 0;
    const { fetch } = createMockFetch(() => {
      step++;
      if (step === 1) {
        return new Response(JSON.stringify({ detail: "Invalid accountId", status: 400 }), {
          status: 400,
          statusText: "Bad Request",
          headers: { "Content-Type": "application/problem+json" },
        });
      }
      if (step === 2) {
        return new Response(null, { status: 401, statusText: "Unauthorized" });
      }
      return new Response("<html>Bad Gateway</html>", {
        status: 502,
        statusText: "Bad Gateway",
        headers: { "Content-Type": "text/html" },
      });
    });

    const client = createClient<SyntheticSchemas>({ baseUrl: "https://api.example.test", fetch });

    const res400 = await client.path("/cost").get({ query: { externalBankAccountId: "bad" } });
    assert(res400.error instanceof ApiResponseError, "400 returns ApiResponseError");
    assertEqual(res400.error.kind, "response", "400 kind");
    assertEqual(res400.data, undefined, "400 has undefined data");
    assertEqual(res400.error.status, 400, "400 status");
    assertEqual(res400.error.body?.detail, "Invalid accountId", "400 ProblemDetails parsed");
    assertEqual(res400.error.message, "HTTP 400 Bad Request", "400 message");

    const res401 = await client.path("/cost").get({ query: { externalBankAccountId: "unauth" } });
    assert(res401.error instanceof ApiResponseError, "401 returns ApiResponseError");
    assertEqual(res401.error.status, 401, "401 status");
    assertEqual(res401.error.body, undefined, "401 empty body is undefined");

    const res502 = await client.path("/cost").get({ query: { externalBankAccountId: "down" } });
    assert(res502.error instanceof ApiResponseError, "502 HTML returns ApiResponseError");
    assertEqual(res502.error.status, 502, "502 status");
    assertEqual(res502.error.rawBody, "<html>Bad Gateway</html>", "502 HTML captured in rawBody");
    passed++;
  }

  // 9. Malformed JSON on 200 -> DecodeError, malformed JSON on 502 -> UnexpectedHttpError, plus HEAD.
  {
    let step = 0;
    const { fetch } = createMockFetch(() => {
      step++;
      if (step === 1) {
        return new Response("{not-json", {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      if (step === 2) {
        return new Response("<html>Bad Gateway</html>", {
          status: 502,
          statusText: "Bad Gateway",
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(null, {
        status: 200,
        headers: { "Content-Type": "application/json", "Content-Length": "999" },
      });
    });
    const client = createClient<SyntheticSchemas>({ baseUrl: "https://api.example.test", fetch });

    const res200 = await client.path("/versions").get();
    assert(res200.error instanceof DecodeError, "invalid JSON on 200 returns DecodeError");
    assertEqual(res200.error.kind, "decode", "200 malformed JSON kind");
    assertEqual(res200.data, undefined, "invalid JSON leaves data undefined");
    assertEqual(res200.error.status, 200, "invalid JSON preserves HTTP status");
    assertEqual(res200.error.body, undefined, "invalid 200 JSON leaves body undefined");
    assertEqual(res200.error.rawBody, "{not-json", "invalid 200 JSON preserves rawText in rawBody");
    assert(res200.response !== undefined, "invalid JSON preserves Response");
    assert(res200.error.cause instanceof SyntaxError, "invalid JSON keeps SyntaxError cause");

    const res502 = await client.path("/versions").get();
    assert(res502.error instanceof UnexpectedHttpError, "malformed JSON on 502 returns UnexpectedHttpError");
    assertEqual(res502.error.kind, "unexpected_http", "502 malformed JSON kind");
    assertEqual(res502.error.status, 502, "502 status preserved");
    assertEqual(res502.error.message, "HTTP 502 Bad Gateway", "502 HTTP message preserved");
    assertEqual(res502.error.body, undefined, "502 malformed JSON leaves body undefined");
    assertEqual(
      res502.error.rawBody,
      "<html>Bad Gateway</html>",
      "502 raw body text preserved in rawBody when JSON parse fails",
    );
    assert(res502.error.cause instanceof SyntaxError, "502 keeps SyntaxError parse cause");

    const headRes = await client.path("/users/{id}").head({ path: { id: "1" } });
    assertEqual(headRes.error, undefined, "HEAD request succeeds even with JSON Content-Type");
    assertEqual(headRes.data, undefined, "HEAD response data is undefined");
    passed++;
  }

  // 10. NetworkError and CancelledError (AbortController + custom abort reason).
  {
    const networkFailure = new TypeError("Failed to fetch");
    const netClient = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      fetch: async () => {
        throw networkFailure;
      },
    });

    const netRes = await netClient.path("/versions").get();
    assert(netRes.error instanceof NetworkError, "network error returns NetworkError");
    assertEqual(netRes.error.kind, "network", "network error kind");
    assertEqual(netRes.error.isNetworkError, true, "isNetworkError helper is true");
    assertEqual(netRes.error.status, undefined, "network error has undefined status");
    assertEqual(netRes.response, undefined, "network error has undefined response");
    assertEqual(netRes.error.cause, networkFailure, "network error preserves cause");

    const controller = new AbortController();
    const abortClient = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      fetch: async (_url, init) => {
        if (init?.signal?.aborted) {
          throw init.signal.reason ?? new DOMException("The operation was aborted", "AbortError");
        }
        throw new Error("expected aborted signal");
      },
    });

    controller.abort("user left screen");
    const abortRes = await abortClient.path("/versions").get({
      signal: controller.signal,
    });
    assert(abortRes.error instanceof CancelledError, "aborted request returns CancelledError");
    assertEqual(abortRes.error.kind, "cancelled", "cancelled error kind");
    assertEqual(abortRes.error.isCancelled, true, "isCancelled helper is true");
    assertEqual(abortRes.error.reason, "user left screen", "custom abort reason preserved");
    assertEqual(abortRes.error.status, undefined, "aborted request has undefined status");
    passed++;
  }

  // 11. Default globalThis.fetch wrapper avoids illegal receiver binding.
  {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ version: "1.0.0" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });

    try {
      const client = createClient<SyntheticSchemas>({ baseUrl: "https://api.example.test" });
      const { data, error } = await client.path("/versions").get();
      assertEqual(error, undefined, "default fetch succeeds");
      assertEqual(data?.version, "1.0.0", "default fetch reads payload");
    } finally {
      globalThis.fetch = originalFetch;
    }
    passed++;
  }

  // 12. error.is(status) works consistently across 400, 409, 401, 502, and network failures.
  {
    let step = 0;
    const { fetch } = createMockFetch(() => {
      step++;
      if (step === 1) {
        return new Response(JSON.stringify({ fields: { item: "required" } }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }
      if (step === 2) {
        return new Response(JSON.stringify({ conflictId: "ord-99" }), {
          status: 409,
          headers: { "Content-Type": "application/json" },
        });
      }
      if (step === 3) {
        return new Response(null, { status: 401 });
      }
      if (step === 4) {
        return new Response("Bad Gateway", {
          status: 502,
          headers: { "Content-Type": "text/plain" },
        });
      }
      return Promise.reject(new TypeError("offline"));
    });

    const client = createClient<SyntheticSchemas>({ baseUrl: "https://api.example.test", fetch });

    const r400 = await client.path("/orders").post({ body: { item: "" } });
    assert(r400.error !== undefined && r400.error.is(400), "400 matches is(400)");
    assert(!r400.error.is(409), "400 does not match is(409)");
    assertEqual(r400.error.body?.fields.item, "required", "400 narrowed body fields readable");

    const r409 = await client.path("/orders").post({ body: { item: "dup" } });
    assert(r409.error !== undefined && r409.error.is(409), "409 matches is(409)");
    assertEqual(r409.error.body?.conflictId, "ord-99", "409 narrowed body conflictId readable");

    const r401 = await client.path("/orders").post({ body: { item: "x" } });
    assert(r401.error !== undefined && r401.error.is(401), "401 matches is(401)");
    assertEqual(r401.error.body, undefined, "401 empty body is undefined");

    const r502 = await client.path("/orders").post({ body: { item: "y" } });
    assert(r502.error !== undefined, "502 returns error");
    assert(!r502.error.is(400) && !r502.error.is(409) && !r502.error.is(401), "502 matches none of declared 4xx");
    assertEqual(r502.error.status, 502, "502 status preserved");

    const rNet = await client.path("/orders").post({ body: { item: "z" } });
    assert(rNet.error instanceof NetworkError, "network failure returns NetworkError");
    assertEqual(rNet.error.status, undefined, "network error status undefined");
    assert(!rNet.error.is(400) && !rNet.error.is(409) && !rNet.error.is(401), "network failure matches none");
    passed++;
  }

  // 13. Dynamic async headers provider, requestInit merging, extra state, and hooks.
  {
    const events: string[] = [];
    let attempt = 0;

    const { fetch, calls } = createMockFetch((call) => {
      attempt++;
      events.push(`fetch:${attempt}:${call.url}`);
      if (attempt === 1) {
        return new Response(null, { status: 401, statusText: "Unauthorized" });
      }
      return new Response(JSON.stringify({ version: "2.0.0" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    });

    const client = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      fetch,
      requestInit: { credentials: "include", cache: "default" },
      headers: async ({ method, path }) => ({
        Authorization: `Bearer initial-${method}-${path}`,
        "X-Source": "dynamic",
      }),
      onRequest: [
        (ctx) => {
          events.push(`onRequest:${ctx.method}:${String(ctx.extra.traceTag)}`);
          ctx.headers.set("X-Hook-Added", "yes");
          ctx.url = `${ctx.url}?fromHook=1`;
          ctx.extra.mutatedInHook = true;
        },
      ],
      onResponse: async (ctx: Readonly<RequestContext>, res) => {
        events.push(`onResponse:${res.status}`);
        if (res.status === 401 && ctx.extra._retried !== true) {
          ctx.extra._retried = true;
          ctx.headers.set("Authorization", "Bearer refreshed");
          return fetch(ctx.url, ctx.init);
        }
        return undefined;
      },
      onError: (_ctx, err) => {
        events.push(`onError:${err.kind}:${err.status ?? "none"}`);
      },
    });

    const callerExtra: Record<string, unknown> = { traceTag: "t1" };
    const okRes = await client.path("/versions").get({
      headers: { "X-Source": "per-request" },
      requestInit: { cache: "no-store" },
      extra: callerExtra,
    });

    assertEqual(okRes.error, undefined, "retry in onResponse recovers 401 into 200");
    assertEqual(okRes.data?.version, "2.0.0", "retried response payload parsed");
    assertEqual(callerExtra.mutatedInHook, undefined, "caller extra object is shallow-copied, not mutated");
    assertEqual(calls[0]?.init.credentials, "include", "config.requestInit merged");
    assertEqual(calls[0]?.init.cache, "no-store", "per-request requestInit overrides config");
    assertEqual(
      (calls[0]?.init.headers as Headers).get("x-source"),
      "per-request",
      "per-request header overrides dynamic headers",
    );
    assertEqual(
      (calls[0]?.init.headers as Headers).get("x-hook-added"),
      "yes",
      "onRequest header mutation sent",
    );
    assertEqual(
      (calls[1]?.init.headers as Headers).get("authorization"),
      "Bearer refreshed",
      "retried request uses updated Authorization header",
    );
    assertDeepEqual(
      events,
      [
        "onRequest:get:t1",
        "fetch:1:https://api.example.test/versions?fromHook=1",
        "onResponse:401",
        "fetch:2:https://api.example.test/versions?fromHook=1",
      ],
      "hook execution order matches",
    );

    // Throwing hooks never reject and classify as UnexpectedClientError(stage: "hook").
    const errorEvents: string[] = [];
    const faultyClient = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      fetch,
      onRequest: () => {
        throw new Error("request hook boom");
      },
      onError: (_ctx, err) => {
        errorEvents.push(err.message);
        throw new Error("error hook boom");
      },
    });

    const hookErrRes = await faultyClient.path("/versions").get();
    assert(hookErrRes.error instanceof UnexpectedClientError, "throwing hook returns UnexpectedClientError");
    assertEqual(hookErrRes.error.kind, "client", "throwing hook kind");
    assertEqual(hookErrRes.error.stage, "hook", "throwing hook stage");
    assertEqual(errorEvents.length, 1, "onError called once");
    assert(
      hookErrRes.error.message.includes("error hook boom"),
      "error from throwing onError hook captured cleanly",
    );

    const headerProviderErrClient = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      fetch,
      headers: async () => {
        throw new Error("token storage failed");
      },
    });
    const headerErrRes = await headerProviderErrClient.path("/versions").get();
    assert(
      headerErrRes.error instanceof UnexpectedClientError,
      "throwing headers provider returns UnexpectedClientError",
    );
    assertEqual(headerErrRes.error.stage, "hook", "throwing headers provider stage is hook");
    passed++;
  }

  // 14. timeoutMs (positive and <= 0) -> TimeoutError and composes with user AbortSignal.
  {
    const timeoutErrors: string[] = [];
    const slowFetch: typeof fetch = (_url, init) =>
      new Promise<Response>((_resolve, reject) => {
        const signal = init?.signal;
        if (signal?.aborted) {
          reject(signal.reason);
          return;
        }
        signal?.addEventListener(
          "abort",
          () => {
            reject(signal.reason);
          },
          { once: true },
        );
      });

    const client = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      fetch: slowFetch,
      timeoutMs: 25,
      onError: (_ctx, err) => {
        timeoutErrors.push(err.kind);
      },
    });

    const timedOut = await client.path("/versions").get();
    assert(timedOut.error instanceof TimeoutError, "timeout returns TimeoutError");
    assertEqual(timedOut.error.kind, "timeout", "timeout kind");
    assertEqual(timedOut.error.isTimeout, true, "isTimeout helper is true");
    assertEqual(timedOut.error.timeoutMs, 25, "timeoutMs preserved");
    assert(timedOut.error.cause instanceof DOMException, "timeout cause is DOMException");
    assertEqual((timedOut.error.cause as DOMException).name, "TimeoutError", "timeout DOMException name");
    assertDeepEqual(timeoutErrors, ["timeout"], "onError invoked with timeout kind");

    const zeroTimeout = await client.path("/versions").get({ timeoutMs: 0 });
    assert(zeroTimeout.error instanceof TimeoutError, "zero timeout immediately yields TimeoutError");
    assertEqual(zeroTimeout.error.timeoutMs, 0, "zero timeoutMs preserved");

    const userController = new AbortController();
    userController.abort(new DOMException("User cancelled", "AbortError"));
    const userAborted = await client.path("/versions").get({
      signal: userController.signal,
      timeoutMs: 0,
    });
    assert(userAborted.error instanceof CancelledError, "pre-aborted signal yields CancelledError even with timeoutMs=0");
    assertEqual(userAborted.error.isCancelled, true, "isCancelled is true");
    assert(userAborted.error.cause instanceof DOMException, "user abort cause preserved");
    assertEqual((userAborted.error.cause as DOMException).name, "AbortError", "user AbortError takes precedence");
    passed++;
  }

  // 15. R4: Array header joining, HeadersInit forms, and Cookie appending without overwriting.
  {
    const { fetch, calls } = createMockFetch(() => new Response(null, { status: 204 }));
    const clientFromHeaders = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      headers: new Headers([["X-Base", "from-headers"]]),
      fetch,
    });

    await clientFromHeaders.path("/users/{id}").get({
      path: { id: "10" },
      headers: {
        "X-Request-Id": "req-arr",
        "X-Multi": ["one", null, undefined, 2],
        Cookie: "theme=dark",
      },
      cookie: {
        session: "tok 1",
      },
    });

    const sent1 = calls[0]?.init.headers as Headers;
    assertEqual(sent1.get("x-base"), "from-headers", "Headers instance base applied");
    assertEqual(sent1.get("x-multi"), "one, 2", "array header joins non-null entries");
    assertEqual(
      sent1.get("cookie"),
      "theme=dark; session=tok%201",
      "options.cookie appends to existing Cookie header",
    );

    const clientFromTuples = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      headers: [["X-Tuple", "tuple-val"]],
      fetch,
    });
    await clientFromTuples.path("/versions").get();
    assertEqual((calls[1]?.init.headers as Headers).get("x-tuple"), "tuple-val", "tuple base headers applied");
    passed++;
  }

  // 16. R5: File/multi-file multipart, FormData passthrough, binary upload, urlencoded variants, and request_build errors.
  {
    const { fetch, calls } = createMockFetch((call) => {
      if (call.url.endsWith("/files-multi")) {
        return new Response(JSON.stringify({ received: 2 }), {
          status: 201,
          headers: { "Content-Type": "application/json" },
        });
      }
      if (call.url.endsWith("/binary-upload")) {
        const bytes = call.init.body as Uint8Array;
        return new Response(JSON.stringify({ size: bytes.byteLength }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    });

    const client = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      headers: { "Content-Type": "application/json" },
      fetch,
    });

    const primaryFile = new File(["pdf-bytes"], "report.pdf", { type: "application/pdf" });
    const att1 = new File(["img-1"], "a.png", { type: "image/png" });
    const att2 = new Blob(["raw-2"], { type: "application/octet-stream" });

    const multiRes = await client.path("/files-multi").post({
      contentType: "multipart/form-data",
      body: {
        primary: primaryFile,
        attachments: [att1, att2],
        count: 3,
        active: true,
        meta: { source: "web" },
      },
    });
    assertEqual(multiRes.error, undefined, "multi-file multipart upload succeeds");
    assertEqual(multiRes.data?.received, 2, "multi-file multipart response decoded");
    const multiForm = calls[0]?.init.body as FormData;
    assert(multiForm instanceof FormData, "multi-file body built as FormData");
    const gotPrimary = multiForm.get("primary") as File;
    assertEqual(gotPrimary.name, "report.pdf", "File name preserved in FormData");
    assertEqual(gotPrimary.type, "application/pdf", "File MIME type preserved in FormData");
    assertEqual(multiForm.getAll("attachments").length, 2, "multi-file array appended");
    assertEqual(multiForm.get("count"), "3", "numeric multipart field stringified");
    assertEqual(multiForm.get("active"), "true", "boolean multipart field stringified");
    assertEqual(multiForm.get("meta"), '{"source":"web"}', "nested object field JSON-encoded");
    assertEqual((calls[0]?.init.headers as Headers).get("content-type"), null, "multipart strips base Content-Type");

    // Pre-built FormData passthrough strips stale base Content-Type.
    const manualForm = new FormData();
    manualForm.set("file", new Blob(["manual"]), "manual.txt");
    await client.path("/optional-upload").post({
      contentType: "multipart/form-data",
      body: manualForm as unknown as { file: Blob },
    });
    assert(calls[1]?.init.body === manualForm, "prebuilt FormData passed directly");
    assertEqual((calls[1]?.init.headers as Headers).get("content-type"), null, "prebuilt FormData strips Content-Type");

    // Raw binary application/octet-stream upload.
    const payload = new Uint8Array([10, 20, 30, 40]);
    const binUploadRes = await client.path("/binary-upload").post({
      contentType: "application/octet-stream",
      body: payload,
    });
    assertEqual(binUploadRes.data?.size, 4, "binary upload byte length matched");
    assertEqual(
      (calls[2]?.init.headers as Headers).get("content-type"),
      "application/octet-stream",
      "octet-stream Content-Type set",
    );

    // Raw string & URLSearchParams for application/x-www-form-urlencoded.
    await client.path("/login").post({
      contentType: "application/x-www-form-urlencoded",
      body: new URLSearchParams({ username: "bob", password: "pw" }) as unknown as {
        username: string;
        password: string;
      },
    });
    assertEqual(
      (calls[3]?.init.body as URLSearchParams).toString(),
      "username=bob&password=pw",
      "URLSearchParams urlencoded passthrough preserved",
    );

    // Invalid bodies -> UnexpectedClientError(stage: "request_build") without calling fetch.
    const callCountBeforeInvalid = calls.length;
    const badMultipart = await client.path("/upload-only").post({
      contentType: "multipart/form-data",
      body: "not-an-object" as unknown as { file: Blob },
    });
    assert(badMultipart.error instanceof UnexpectedClientError, "bad multipart body yields UnexpectedClientError");
    assertEqual(badMultipart.error.stage, "request_build", "bad multipart stage is request_build");

    const badUrlEncoded = await client.path("/login").post({
      contentType: "application/x-www-form-urlencoded",
      body: 123 as unknown as { username: string; password: string },
    });
    assert(badUrlEncoded.error instanceof UnexpectedClientError, "bad urlencoded yields UnexpectedClientError");
    assertEqual(badUrlEncoded.error.stage, "request_build", "bad urlencoded stage is request_build");

    const circular: Record<string, unknown> = {};
    circular.self = circular;
    const badJson = await client.path("/cost").post({
      body: circular as unknown as { costFixed: number },
    });
    assert(badJson.error instanceof UnexpectedClientError, "circular JSON yields UnexpectedClientError");
    assertEqual(badJson.error.stage, "request_build", "circular JSON stage is request_build");
    assertEqual(calls.length, callCountBeforeInvalid, "transport never invoked on request_build failures");
    passed++;
  }

  // 17. R6: Binary (Blob) & CSV downloads, plus whitespace JSON, 205/304, and Content-Length: 0.
  {
    let step = 0;
    const { fetch } = createMockFetch(() => {
      step++;
      if (step === 1) {
        return new Response(new Uint8Array([1, 2, 3, 4]), {
          status: 200,
          headers: { "Content-Type": "application/octet-stream" },
        });
      }
      if (step === 2) {
        return new Response("a,b\n1,2\n", {
          status: 200,
          headers: { "Content-Type": "text/csv" },
        });
      }
      if (step === 3) {
        return new Response("   \n\t ", {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(null, { status: 205 });
    });

    const client = createClient<SyntheticSchemas>({ baseUrl: "https://api.example.test", fetch });

    const binRes = await client.path("/export.bin").get();
    assertEqual(binRes.error, undefined, "binary download succeeds");
    assert(binRes.data instanceof Blob, "binary download returns Blob");
    const bytes = new Uint8Array(await binRes.data.arrayBuffer());
    assertDeepEqual(Array.from(bytes), [1, 2, 3, 4], "downloaded Blob bytes match");

    const csvRes = await client.path("/export.csv").get();
    assertEqual(csvRes.data, "a,b\n1,2\n", "text/csv response decoded as string");

    const wsJsonRes = await client.path("/versions").get();
    assertEqual(wsJsonRes.error, undefined, "whitespace JSON succeeds");
    assertEqual(wsJsonRes.data, undefined, "whitespace JSON yields undefined");

    const resetRes = await client.path("/versions").get();
    assertEqual(resetRes.error, undefined, "205 Reset Content succeeds");
    assertEqual(resetRes.data, undefined, "205 yields undefined data");
    passed++;
  }

  // 18. R8: Chained onRequest/onResponse hooks, header delete, body rewrite, hook & stream errors.
  {
    const trace: string[] = [];
    const { fetch, calls } = createMockFetch(() =>
      new Response(JSON.stringify({ id: "u-1", name: "Raw" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );

    const client = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      headers: {
        "X-Drop-Me": "should-be-deleted",
        "X-Override": "initial",
      },
      fetch,
      onRequest: [
        async (ctx) => {
          trace.push("req-1");
          ctx.headers.delete("X-Drop-Me");
          ctx.headers.set("X-Override", "from-hook-1");
          ctx.headers.set("X-From-Hook-1", "a");
          ctx.url = `${ctx.url}?step=1`;
          ctx.init.body = JSON.stringify({ name: "ModifiedByHook" });
          ctx.extra.step = 1;
        },
        (ctx) => {
          trace.push(`req-2:${ctx.headers.get("x-override")}:${String(ctx.extra.step)}`);
          ctx.headers.set("X-From-Hook-2", "b");
          ctx.url = `${ctx.url}&step2=true`;
        },
      ],
      onResponse: [
        (_ctx, _res) => {
          trace.push("res-1");
          return new Response(JSON.stringify({ id: "u-1", name: "Replaced-1" }), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          });
        },
        async (_ctx, res) => {
          trace.push("res-2");
          const prev = (await res.json()) as { id: string; name: string };
          return new Response(JSON.stringify({ id: prev.id, name: `${prev.name}+2` }), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          });
        },
      ],
    });

    const callerExtra: Record<string, unknown> = { caller: true };
    const chainedRes = await client.path("/users/{id}").put({
      path: { id: "u-1" },
      body: { name: "Original" },
      extra: callerExtra,
    });

    assertEqual(chainedRes.error, undefined, "chained hooks succeed");
    assertEqual(chainedRes.data?.name, "Replaced-1+2", "chained onResponse replacements observed");
    assertEqual(callerExtra.step, undefined, "caller extra untouched by hook mutation");
    assertEqual(
      calls[0]?.url,
      "https://api.example.test/users/u-1?step=1&step2=true",
      "chained onRequest URL rewrites preserved",
    );
    assertEqual(calls[0]?.init.body, '{"name":"ModifiedByHook"}', "onRequest body mutation sent");
    const sentHeaders = calls[0]?.init.headers as Headers;
    assertEqual(sentHeaders.get("x-drop-me"), null, "onRequest deleted header omitted");
    assertEqual(sentHeaders.get("x-override"), "from-hook-1", "onRequest header override sent");
    assertEqual(sentHeaders.get("x-from-hook-1"), "a", "hook 1 header preserved");
    assertEqual(sentHeaders.get("x-from-hook-2"), "b", "hook 2 header preserved");
    assertDeepEqual(
      trace,
      ["req-1", "req-2:from-hook-1:1", "res-1", "res-2"],
      "chained hook order verified",
    );

    // Throwing onResponse hook -> UnexpectedClientError(stage: "hook") with response preserved.
    const badResHookClient = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      fetch: async () => new Response(JSON.stringify({ version: "1.0" }), { status: 200 }),
      onResponse: () => {
        throw new Error("response hook failed");
      },
    });
    const badResHook = await badResHookClient.path("/versions").get();
    assert(badResHook.error instanceof UnexpectedClientError, "throwing onResponse yields UnexpectedClientError");
    assertEqual(badResHook.error.stage, "hook", "throwing onResponse stage is hook");
    assertEqual(badResHook.error.status, 200, "throwing onResponse preserves status");
    assert(badResHook.response !== undefined, "throwing onResponse preserves Response");

    // Broken response stream during parse -> UnexpectedClientError(stage: "internal").
    const brokenStreamResponse = {
      ok: true,
      status: 200,
      statusText: "OK",
      headers: new Headers({ "Content-Type": "application/json" }),
      text: async () => {
        throw new Error("stream read interrupted");
      },
    } as unknown as Response;
    const brokenStreamClient = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      fetch: async () => brokenStreamResponse,
    });
    const streamRes = await brokenStreamClient.path("/versions").get();
    assert(streamRes.error instanceof UnexpectedClientError, "broken stream yields UnexpectedClientError");
    assertEqual(streamRes.error.stage, "internal", "broken stream stage is internal");
    assertEqual(streamRes.error.status, 200, "broken stream preserves status");
    passed++;
  }

  // 19. R9: Bounded 503 retries, concurrent single-flight 401 refresh, and transport-level NetworkError retries.
  {
    // 19a. Bounded 503 retry recovering on attempt 3 and stopping at maxRetries.
    let retryServerCalls = 0;
    let alwaysFail = false;
    const { fetch: retryFetch } = createMockFetch(() => {
      retryServerCalls++;
      if (alwaysFail || retryServerCalls < 3) {
        return new Response(JSON.stringify({ code: "busy" }), {
          status: 503,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    });

    const boundedRetryClient = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      fetch: retryFetch,
      onResponse: async (ctx, res) => {
        let current = res;
        let retries = (ctx.extra.retries as number | undefined) ?? 0;
        while (current.status === 503 && retries < 2) {
          retries++;
          ctx.extra.retries = retries;
          current = await retryFetch(ctx.url, ctx.init);
        }
        return current === res ? undefined : current;
      },
    });

    const recovered = await boundedRetryClient.path("/retryable").get();
    assertEqual(recovered.data?.ok, true, "bounded 503 retry recovers on 3rd attempt");
    assertEqual(retryServerCalls, 3, "server called 3 times to recover");

    alwaysFail = true;
    const beforeExhaust = retryServerCalls;
    const exhausted = await boundedRetryClient.path("/retryable").get();
    assert(exhausted.error instanceof ApiResponseError, "exhausted retry returns final ApiResponseError");
    assertEqual(exhausted.error.status, 503, "exhausted retry preserves 503");
    assertEqual(retryServerCalls - beforeExhaust, 3, "bounded to 1 initial + 2 retries");

    // 19b. Concurrent single-flight 401 refresh + retry-once guard.
    let activeToken = "expired-token";
    let refreshCount = 0;
    let inflightRefresh: Promise<boolean> | null = null;
    let forcePersistent401 = false;

    const singleFlightFetch = async (_input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
      const headers = new Headers(init?.headers);
      if (forcePersistent401 || headers.get("authorization") !== "Bearer fresh-token") {
        return new Response(null, { status: 401, statusText: "Unauthorized" });
      }
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    };

    const runSingleFlightRefresh = (): Promise<boolean> => {
      if (inflightRefresh) return inflightRefresh;
      inflightRefresh = (async () => {
        refreshCount++;
        await new Promise((resolve) => setTimeout(resolve, 15));
        activeToken = "fresh-token";
        return true;
      })().finally(() => {
        inflightRefresh = null;
      });
      return inflightRefresh;
    };

    const authRetryClient = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      fetch: singleFlightFetch,
      headers: () => ({ Authorization: `Bearer ${activeToken}` }),
      onResponse: async (ctx, res) => {
        if (res.status !== 401 || ctx.extra._retried === true) return undefined;
        await runSingleFlightRefresh();
        ctx.extra._retried = true;
        ctx.headers.set("Authorization", `Bearer ${activeToken}`);
        return singleFlightFetch(ctx.url, ctx.init);
      },
    });

    const [p1, p2] = await Promise.all([
      authRetryClient.path("/retryable").get(),
      authRetryClient.path("/retryable").get(),
    ]);
    assertEqual(p1.data?.ok, true, "concurrent request 1 succeeds after single-flight refresh");
    assertEqual(p2.data?.ok, true, "concurrent request 2 succeeds after single-flight refresh");
    assertEqual(refreshCount, 1, "concurrent 401 responses share single refresh call");

    forcePersistent401 = true;
    const persistent401 = await authRetryClient.path("/retryable").get();
    assertEqual(persistent401.error?.status, 401, "persistent 401 stops after retry-once guard");
    assertEqual(refreshCount, 2, "refresh called once more then stopped by _retried guard");

    // 19c. Transport-level retry wrapper for transient NetworkError.
    let netAttempts = 0;
    let alwaysOffline = false;
    const retryingFetch: typeof fetch = async (input, init) => {
      for (let attempt = 0; ; attempt++) {
        netAttempts++;
        try {
          if (alwaysOffline || netAttempts === 1) {
            throw new TypeError("transient socket reset");
          }
          return new Response(JSON.stringify({ ok: true }), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          });
        } catch (err) {
          if (attempt >= 1) throw err;
        }
      }
    };
    const netRetryClient = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      fetch: retryingFetch,
    });
    const netRecovered = await netRetryClient.path("/retryable").get();
    assertEqual(netRecovered.data?.ok, true, "transport retry recovers transient network error");
    assertEqual(netAttempts, 2, "transport retried once to recover");

    alwaysOffline = true;
    const netFailed = await netRetryClient.path("/retryable").get();
    assert(netFailed.error instanceof NetworkError, "exhausted transport retry yields NetworkError");
    passed++;
  }

  // 20. R10: Mid-flight AbortController cancellation & per-request timeoutMs overriding config.timeoutMs.
  {
    const controller = new AbortController();
    const pendingClient = createClient<SyntheticSchemas>({
      baseUrl: "https://api.example.test",
      timeoutMs: 5000,
      fetch: (_url, init) =>
        new Promise<Response>((_resolve, reject) => {
          const signal = init?.signal;
          if (signal?.aborted) {
            reject(signal.reason);
            return;
          }
          signal?.addEventListener("abort", () => reject(signal.reason), { once: true });
        }),
    });

    setTimeout(() => controller.abort("navigated away"), 15);
    const midCancelled = await pendingClient.path("/versions").get({ signal: controller.signal });
    assert(midCancelled.error instanceof CancelledError, "mid-flight abort yields CancelledError");
    assertEqual(midCancelled.error.reason, "navigated away", "mid-flight abort reason preserved");

    const perReqTimeout = await pendingClient.path("/versions").get({ timeoutMs: 20 });
    assert(perReqTimeout.error instanceof TimeoutError, "per-request timeoutMs overrides larger config timeout");
    assertEqual(perReqTimeout.error.timeoutMs, 20, "per-request timeoutMs value preserved");
    passed++;
  }

  console.log(`client-ts tests passed (${passed} cases)`);
}

runTests().catch((err) => {
  console.error(err);
  throw err;
});
