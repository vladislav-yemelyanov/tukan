import {
  ApiError,
  ApiResponseError,
  CancelledError,
  DecodeError,
  NetworkError,
  TimeoutError,
  UnexpectedClientError,
  UnexpectedHttpError,
  type ClientError,
  type ClientErrorStage,
  type ClientResult,
} from "./error.js";
import type {
  Client,
  ClientConfig,
  ExtractOperations,
  FetchRequestOptions,
  HeadersProvider,
  HttpMethod,
  OnErrorHook,
  PathClient,
  RequestContext,
} from "./types.js";

interface RawRequestOptions {
  path?: Record<string, unknown> | undefined;
  query?: Record<string, unknown> | undefined;
  headers?: unknown;
  cookie?: Record<string, unknown> | undefined;
  contentType?: string | undefined;
  body?: unknown;
  signal?: AbortSignal | undefined;
  timeoutMs?: number | undefined;
  requestInit?: FetchRequestOptions | undefined;
  extra?: Record<string, unknown> | undefined;
}

class RequestBuildError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RequestBuildError";
  }
}

type ParsedBodyResult =
  | { parsed: unknown; parseFailed: false; rawText: undefined; error: undefined }
  | { parsed: undefined; parseFailed: true; rawText: string; error: unknown };

const HTTP_METHODS: readonly HttpMethod[] = [
  "get",
  "post",
  "put",
  "patch",
  "delete",
  "head",
  "options",
  "trace",
];

const defaultFetch: typeof fetch = (input, init) => globalThis.fetch(input, init);

function mimeType(contentType: string): string {
  const semi = contentType.indexOf(";");
  const raw = semi === -1 ? contentType : contentType.slice(0, semi);
  return raw.trim().toLowerCase();
}

function isJsonMime(mime: string): boolean {
  return mime === "application/json" || (mime.startsWith("application/") && mime.endsWith("+json"));
}

function serializeParamValue(value: unknown): string {
  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value === "object" && value !== null) {
    return JSON.stringify(value);
  }

  return String(value);
}

function toSearchParams(record: Record<string, unknown>): URLSearchParams {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(record)) {
    if (value === undefined || value === null) continue;

    if (Array.isArray(value)) {
      for (const item of value) {
        if (item !== undefined && item !== null) {
          params.append(key, serializeParamValue(item));
        }
      }
    } else {
      params.append(key, serializeParamValue(value));
    }
  }

  return params;
}

function buildUrl(
  baseUrl: string,
  template: string,
  pathParams?: Record<string, unknown>,
  query?: Record<string, unknown>,
): string {
  const resolvedPath = template.replace(/\{([^}]+)\}/g, (_match, key: string) => {
    const value = pathParams?.[key];
    if (value === undefined || value === null) {
      throw new RequestBuildError(`Missing required path parameter "${key}" for ${template}`);
    }

    return encodeURIComponent(String(value));
  });

  const normalizedBase = baseUrl.replace(/\/+$/, "");
  const pathPart =
    normalizedBase.length > 0 && !resolvedPath.startsWith("/")
      ? `/${resolvedPath}`
      : resolvedPath;

  let url = `${normalizedBase}${pathPart}`;

  if (query !== undefined) {
    const queryString = toSearchParams(query).toString();
    if (queryString.length > 0) {
      url += (url.includes("?") ? "&" : "?") + queryString;
    }
  }

  return url;
}

function applyHeaders(target: Headers, source: unknown): void {
  if (source === undefined || source === null) return;

  if (source instanceof Headers) {
    source.forEach((value, key) => target.set(key, value));
    return;
  }

  if (Array.isArray(source)) {
    for (const entry of source) {
      if (Array.isArray(entry) && entry.length >= 2) {
        target.set(String(entry[0]), String(entry[1]));
      }
    }
    return;
  }

  if (typeof source === "object") {
    for (const [key, value] of Object.entries(source)) {
      if (value === undefined || value === null) continue;

      if (Array.isArray(value)) {
        const items = value
          .filter((item) => item !== undefined && item !== null)
          .map(serializeParamValue);
        if (items.length > 0) {
          target.set(key, items.join(", "));
        }
      } else {
        target.set(key, serializeParamValue(value));
      }
    }
  }
}

function buildHeaders(
  baseHeaders: unknown,
  requestHeaders: unknown,
  cookies: Record<string, unknown> | undefined,
): { headers: Headers; hasRequestContentType: boolean } {
  const headers = new Headers();
  applyHeaders(headers, baseHeaders);

  const perRequest = new Headers();
  applyHeaders(perRequest, requestHeaders);
  const hasRequestContentType = perRequest.has("content-type");
  perRequest.forEach((value, key) => headers.set(key, value));

  if (cookies !== undefined) {
    const pairs: string[] = [];
    for (const [key, value] of Object.entries(cookies)) {
      if (value !== undefined && value !== null) {
        pairs.push(`${key}=${encodeURIComponent(serializeParamValue(value))}`);
      }
    }

    if (pairs.length > 0) {
      const existing = headers.get("cookie");
      headers.set("cookie", existing ? `${existing}; ${pairs.join("; ")}` : pairs.join("; "));
    }
  }

  return { headers, hasRequestContentType };
}

function appendFormField(form: FormData, key: string, value: unknown): void {
  if (value instanceof Blob) {
    form.append(key, value);
    return;
  }

  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    form.append(key, String(value));
    return;
  }

  form.append(key, JSON.stringify(value));
}

function toFormData(body: unknown): FormData {
  if (body instanceof FormData) return body;

  const form = new FormData();
  if (typeof body !== "object" || body === null) {
    throw new RequestBuildError("multipart/form-data body must be an object or FormData");
  }

  for (const [key, value] of Object.entries(body)) {
    if (value === undefined || value === null) continue;

    if (Array.isArray(value)) {
      for (const item of value) {
        if (item !== undefined && item !== null) {
          appendFormField(form, key, item);
        }
      }
    } else {
      appendFormField(form, key, value);
    }
  }

  return form;
}

function toUrlEncoded(body: unknown): URLSearchParams | string {
  if (body instanceof URLSearchParams || typeof body === "string") {
    return body;
  }

  if (typeof body !== "object" || body === null) {
    throw new RequestBuildError(
      "application/x-www-form-urlencoded body must be an object, URLSearchParams, or string",
    );
  }

  return toSearchParams(body as Record<string, unknown>);
}

function applyContentType(
  headers: Headers,
  explicitContentType: string | undefined,
  fallbackContentType: string,
  hasRequestContentType: boolean,
): void {
  if (explicitContentType !== undefined && !hasRequestContentType) {
    headers.set("content-type", explicitContentType);
    return;
  }

  if (!headers.has("content-type")) {
    headers.set("content-type", fallbackContentType);
  }
}

function serializeBody(
  body: unknown,
  contentType: string | undefined,
  headers: Headers,
  hasRequestContentType: boolean,
): BodyInit | undefined {
  if (body === undefined) return undefined;

  if (body instanceof FormData) {
    if (!contentType || mimeType(contentType) === "multipart/form-data") {
      // Let fetch attach the multipart boundary automatically.
      headers.delete("content-type");
    } else if (!hasRequestContentType) {
      headers.set("content-type", contentType);
    }
    return body;
  }

  const effectiveMime = mimeType(contentType ?? headers.get("content-type") ?? "application/json");

  if (effectiveMime === "multipart/form-data") {
    headers.delete("content-type");
    return toFormData(body);
  }

  if (effectiveMime === "application/x-www-form-urlencoded") {
    applyContentType(headers, contentType, "application/x-www-form-urlencoded", hasRequestContentType);
    return toUrlEncoded(body);
  }

  if (isJsonMime(effectiveMime)) {
    applyContentType(headers, contentType, "application/json", hasRequestContentType);
    return JSON.stringify(body);
  }

  if (contentType !== undefined && !hasRequestContentType) {
    headers.set("content-type", contentType);
  }

  return body as BodyInit;
}

function httpErrorMessage(response: Response): string {
  return response.statusText
    ? `HTTP ${response.status} ${response.statusText}`
    : `HTTP ${response.status}`;
}

async function parseResponseBody(
  response: Response,
  method: HttpMethod,
): Promise<ParsedBodyResult> {
  if (
    method === "head" ||
    response.status === 204 ||
    response.status === 205 ||
    response.status === 304 ||
    response.headers.get("content-length")?.trim() === "0"
  ) {
    return { parsed: undefined, parseFailed: false, rawText: undefined, error: undefined };
  }

  const mime = mimeType(response.headers.get("content-type") ?? "");

  if (isJsonMime(mime)) {
    const text = await response.text();
    if (text.trim().length === 0) {
      return { parsed: undefined, parseFailed: false, rawText: undefined, error: undefined };
    }

    try {
      return {
        parsed: JSON.parse(text) as unknown,
        parseFailed: false,
        rawText: undefined,
        error: undefined,
      };
    } catch (error) {
      return { parsed: undefined, parseFailed: true, rawText: text, error };
    }
  }

  if (mime === "" || mime.startsWith("text/")) {
    const text = await response.text();
    return {
      parsed: text.length === 0 ? undefined : text,
      parseFailed: false,
      rawText: undefined,
      error: undefined,
    };
  }

  const blob = await response.blob();
  return {
    parsed: blob.size === 0 ? undefined : blob,
    parseFailed: false,
    rawText: undefined,
    error: undefined,
  };
}

function isReadonlyArray<T>(value: T | readonly T[]): value is readonly T[] {
  return Array.isArray(value);
}

function toHookList<T>(hooks: T | readonly T[] | undefined): readonly T[] {
  if (hooks === undefined) return [];
  return isReadonlyArray(hooks) ? hooks : [hooks];
}

function createRequestSignal(
  userSignal: AbortSignal | undefined,
  timeoutMs: number | undefined,
): { signal: AbortSignal | undefined; cleanup: () => void; isTimedOut: () => boolean } {
  let didTimeout = false;

  if (timeoutMs === undefined) {
    return { signal: userSignal, cleanup: () => {}, isTimedOut: () => didTimeout };
  }

  const controller = new AbortController();
  const onUserAbort = () => controller.abort(userSignal?.reason);

  if (userSignal !== undefined) {
    if (userSignal.aborted) {
      controller.abort(userSignal.reason);
      return { signal: controller.signal, cleanup: () => {}, isTimedOut: () => didTimeout };
    }
    userSignal.addEventListener("abort", onUserAbort, { once: true });
  }

  if (timeoutMs <= 0) {
    didTimeout = true;
    controller.abort(new DOMException("Request timed out", "TimeoutError"));
    return {
      signal: controller.signal,
      cleanup: () => userSignal?.removeEventListener("abort", onUserAbort),
      isTimedOut: () => didTimeout,
    };
  }

  const timer = setTimeout(() => {
    didTimeout = true;
    controller.abort(new DOMException(`Request timed out after ${timeoutMs}ms`, "TimeoutError"));
  }, timeoutMs);

  const cleanup = () => {
    clearTimeout(timer);
    userSignal?.removeEventListener("abort", onUserAbort);
  };

  return { signal: controller.signal, cleanup, isTimedOut: () => didTimeout };
}

async function resolveBaseHeaders(
  provider: HeadersProvider | undefined,
  method: HttpMethod,
  path: string,
  url: string,
): Promise<unknown> {
  if (typeof provider === "function") {
    return provider({ method, path, url });
  }
  return provider;
}

function errorDetail(thrown: unknown): string {
  return thrown instanceof Error && thrown.message ? thrown.message : String(thrown);
}

function classifyThrown(
  thrown: unknown,
  options: {
    response: Response | undefined;
    stage: ClientErrorStage;
    inTransport: boolean;
    didTimeout: boolean;
    userSignal: AbortSignal | undefined;
    timeoutMs: number | undefined;
  },
): ClientError {
  if (thrown instanceof ApiError) {
    return thrown as ClientError;
  }

  if (options.didTimeout || (thrown instanceof DOMException && thrown.name === "TimeoutError")) {
    return new TimeoutError(errorDetail(thrown), {
      timeoutMs: options.timeoutMs,
      cause: thrown,
    });
  }

  if (
    options.userSignal?.aborted ||
    (thrown instanceof DOMException && thrown.name === "AbortError")
  ) {
    const reason = options.userSignal?.aborted ? options.userSignal.reason : thrown;
    const detail =
      reason instanceof Error && reason.message
        ? reason.message
        : reason !== undefined
          ? String(reason)
          : errorDetail(thrown);
    return new CancelledError(detail, { reason, cause: thrown });
  }

  if (options.inTransport) {
    return new NetworkError(`Network request failed: ${errorDetail(thrown)}`, { cause: thrown });
  }

  if (thrown instanceof RequestBuildError) {
    return new UnexpectedClientError(thrown.message, {
      stage: "request_build",
      cause: thrown,
    });
  }

  const message = options.response
    ? `Failed to process HTTP ${options.response.status} response: ${errorDetail(thrown)}`
    : `Request failed: ${errorDetail(thrown)}`;

  return new UnexpectedClientError(message, {
    stage: options.stage,
    response: options.response,
    cause: thrown,
  });
}

async function notifyErrorHooks(
  hooks: readonly OnErrorHook[],
  context: Readonly<RequestContext>,
  error: ClientError,
): Promise<ClientError> {
  try {
    for (const hook of hooks) {
      await hook(context, error);
    }
    return error;
  } catch (hookFailure) {
    return new UnexpectedClientError(`onError hook failed: ${errorDetail(hookFailure)}`, {
      stage: "hook",
      response: error.response,
      cause: hookFailure,
    });
  }
}

export function createClient<TSchema>(config: ClientConfig): Client<ExtractOperations<TSchema>> {
  const transport = config.fetch ?? defaultFetch;
  const onRequestHooks = toHookList(config.onRequest);
  const onResponseHooks = toHookList(config.onResponse);
  const onErrorHooks = toHookList(config.onError);

  async function executeRequest(
    method: HttpMethod,
    template: string,
    options?: RawRequestOptions,
  ): Promise<ClientResult<unknown>> {
    let response: Response | undefined;
    let context: RequestContext | undefined;
    let stage: ClientErrorStage = "request_build";
    let inTransport = false;

    const effectiveTimeoutMs = options?.timeoutMs ?? config.timeoutMs;
    const { signal, cleanup, isTimedOut } = createRequestSignal(
      options?.signal,
      effectiveTimeoutMs,
    );

    try {
      const url = buildUrl(config.baseUrl, template, options?.path, options?.query);
      if (typeof config.headers === "function") {
        stage = "hook";
      }
      const baseHeaders = await resolveBaseHeaders(config.headers, method, template, url);

      stage = "request_build";
      const { headers, hasRequestContentType } = buildHeaders(
        baseHeaders,
        options?.headers,
        options?.cookie,
      );
      const body = serializeBody(options?.body, options?.contentType, headers, hasRequestContentType);

      const init: RequestInit = {
        ...config.requestInit,
        ...options?.requestInit,
        method: method.toUpperCase(),
        headers,
      };
      if (body !== undefined) {
        init.body = body;
      }
      if (signal !== undefined) {
        init.signal = signal;
      }

      const extra = options?.extra ? { ...options.extra } : {};
      context = { method, path: template, url, headers, init, extra };

      stage = "hook";
      for (const hook of onRequestHooks) {
        await hook(context);
      }

      stage = "internal";
      inTransport = true;
      response = await transport(context.url, context.init);
      inTransport = false;

      stage = "hook";
      for (const hook of onResponseHooks) {
        const nextResponse = await hook(context, response);
        if (nextResponse !== undefined) {
          response = nextResponse;
        }
      }

      stage = "internal";
      const parsedResult = await parseResponseBody(response, method);

      if (!response.ok) {
        const httpError: ClientError = parsedResult.parseFailed
          ? new UnexpectedHttpError(httpErrorMessage(response), {
              status: response.status,
              response,
              rawBody: parsedResult.rawText,
              cause: parsedResult.error,
            })
          : new ApiResponseError(httpErrorMessage(response), {
              status: response.status,
              response,
              body: parsedResult.parsed,
              rawBody: parsedResult.parsed,
            });
        const finalError = await notifyErrorHooks(onErrorHooks, context, httpError);
        return { data: undefined, error: finalError, response };
      }

      if (parsedResult.parseFailed) {
        const decodeError = new DecodeError(
          `Failed to parse JSON response (HTTP ${response.status})`,
          {
            status: response.status,
            response,
            rawBody: parsedResult.rawText,
            cause: parsedResult.error,
          },
        );
        const finalError = await notifyErrorHooks(onErrorHooks, context, decodeError);
        return { data: undefined, error: finalError, response };
      }

      return { data: parsedResult.parsed, error: undefined, response };
    } catch (thrown) {
      const error = classifyThrown(thrown, {
        response,
        stage,
        inTransport,
        didTimeout: isTimedOut(),
        userSignal: options?.signal,
        timeoutMs: effectiveTimeoutMs,
      });
      const errorResponse = error.response ?? response;
      const fallbackContext: RequestContext = context ?? {
        method,
        path: template,
        url: template,
        headers: new Headers(),
        init: { method: method.toUpperCase() },
        extra: options?.extra ? { ...options.extra } : {},
      };
      const finalError = await notifyErrorHooks(onErrorHooks, fallbackContext, error);

      return {
        data: undefined,
        error: finalError,
        response: errorResponse,
      };
    } finally {
      cleanup();
    }
  }

  return {
    path(template) {
      const methods: Record<string, (options?: RawRequestOptions) => Promise<ClientResult<unknown>>> = {};

      for (const method of HTTP_METHODS) {
        methods[method] = (options) => executeRequest(method, template, options);
      }

      return methods as unknown as PathClient<ExtractOperations<TSchema>, typeof template>;
    },
  };
}
