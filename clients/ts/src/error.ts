type DefinedValues<TMap> = Exclude<TMap[keyof TMap], undefined>;

export type ErrorMapBody<TMap> = [DefinedValues<TMap>] extends [never]
  ? unknown
  : DefinedValues<TMap>;

export type ClientErrorStage = "request_build" | "hook" | "internal";

export type ApiErrorKind =
  | "response"
  | "unexpected_http"
  | "network"
  | "timeout"
  | "cancelled"
  | "decode"
  | "client";

export interface ApiErrorOptions<TBody = unknown> {
  status?: number | undefined;
  body?: TBody | undefined;
  rawBody?: unknown;
  response?: Response | undefined;
  cause?: unknown;
}

/**
 * Base categorized error returned inside `ClientResult` for all `createClient` failures.
 */
export abstract class ApiError<TMap = Record<never, never>> extends Error {
  abstract readonly kind: ApiErrorKind;
  readonly status: number | undefined;
  readonly body: ErrorMapBody<TMap> | undefined;
  readonly rawBody: unknown;
  readonly response: Response | undefined;
  override readonly cause: unknown;

  constructor(message: string, options?: ApiErrorOptions<ErrorMapBody<TMap>>) {
    if (options?.cause === undefined) {
      super(message);
    } else {
      super(message, { cause: options.cause });
    }

    this.name = new.target.name;
    this.status = options?.status;
    this.body = options?.body;
    this.rawBody = options?.rawBody;
    this.response = options?.response;
    this.cause = options?.cause;
  }

  isStatus(code: number): boolean {
    return this.status === code;
  }

  get isNetworkError(): boolean {
    return this.kind === "network";
  }

  get isTimeout(): boolean {
    return this.kind === "timeout";
  }

  get isCancelled(): boolean {
    return this.kind === "cancelled";
  }

  /**
   * Narrows `kind`, `status`, `response`, and `body` to the schema declared for a specific HTTP error status.
   */
  is<TStatus extends Extract<keyof TMap, number>>(
    status: TStatus,
  ): this is ApiResponseError<TMap> & {
    readonly kind: "response";
    readonly status: TStatus;
    readonly body: Extract<TMap[TStatus], ErrorMapBody<TMap>> | undefined;
    readonly response: Response;
  } {
    return this.kind === "response" && this.status === status;
  }
}

/**
 * HTTP non-2xx error whose body parsed cleanly (expected API error).
 */
export class ApiResponseError<TMap = Record<never, never>> extends ApiError<TMap> {
  override readonly kind = "response" as const;
  declare readonly status: number;
  declare readonly response: Response;
  declare readonly body: ErrorMapBody<TMap> | undefined;

  constructor(
    message: string,
    options: {
      status: number;
      response: Response;
      body?: ErrorMapBody<TMap> | undefined;
      rawBody?: unknown;
      cause?: unknown;
    },
  ) {
    super(message, options);
  }
}

/**
 * Unexpected HTTP non-2xx error (e.g. malformed JSON on an error response or unreadable error body).
 */
export class UnexpectedHttpError<TMap = Record<never, never>> extends ApiError<TMap> {
  override readonly kind = "unexpected_http" as const;
  declare readonly status: number;
  declare readonly response: Response;
  declare readonly body: undefined;

  constructor(
    message: string,
    options: {
      status: number;
      response: Response;
      rawBody?: unknown;
      cause?: unknown;
    },
  ) {
    super(message, options);
  }
}

/**
 * Transport-level failure before an HTTP response arrived (offline, DNS, connection refused, TLS).
 */
export class NetworkError<TMap = Record<never, never>> extends ApiError<TMap> {
  override readonly kind = "network" as const;
  declare readonly status: undefined;
  declare readonly response: undefined;
  declare readonly body: undefined;

  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
  }
}

/**
 * Request exceeded `timeoutMs` or `ClientConfig.timeoutMs`.
 */
export class TimeoutError<TMap = Record<never, never>> extends ApiError<TMap> {
  override readonly kind = "timeout" as const;
  readonly timeoutMs: number | undefined;
  declare readonly status: undefined;
  declare readonly response: undefined;
  declare readonly body: undefined;

  constructor(message: string, options?: { timeoutMs?: number | undefined; cause?: unknown }) {
    super(message, options);
    this.timeoutMs = options?.timeoutMs;
  }
}

/**
 * Request aborted via `AbortSignal`.
 */
export class CancelledError<TMap = Record<never, never>> extends ApiError<TMap> {
  override readonly kind = "cancelled" as const;
  readonly reason: unknown;
  declare readonly status: undefined;
  declare readonly response: undefined;
  declare readonly body: undefined;

  constructor(message: string, options?: { reason?: unknown; cause?: unknown }) {
    super(message, options);
    this.reason = options?.reason;
  }
}

/**
 * Server returned 2xx, but JSON response parsing failed.
 */
export class DecodeError<TMap = Record<never, never>> extends ApiError<TMap> {
  override readonly kind = "decode" as const;
  declare readonly status: number;
  declare readonly response: Response;
  declare readonly body: undefined;

  constructor(
    message: string,
    options: {
      status: number;
      response: Response;
      rawBody?: unknown;
      cause?: unknown;
    },
  ) {
    super(message, options);
  }
}

/**
 * Client-side failure during request building, hooks, response stream reading, or internal errors.
 */
export class UnexpectedClientError<TMap = Record<never, never>> extends ApiError<TMap> {
  override readonly kind = "client" as const;
  readonly stage: ClientErrorStage;
  declare readonly body: undefined;

  constructor(
    message: string,
    options: {
      stage: ClientErrorStage;
      response?: Response | undefined;
      cause?: unknown;
    },
  ) {
    super(message, {
      status: options.response?.status,
      response: options.response,
      cause: options.cause,
    });
    this.stage = options.stage;
  }
}

export type ClientError<TMap = Record<never, never>> =
  | ApiResponseError<TMap>
  | UnexpectedHttpError<TMap>
  | NetworkError<TMap>
  | TimeoutError<TMap>
  | CancelledError<TMap>
  | DecodeError<TMap>
  | UnexpectedClientError<TMap>;

export type ClientResult<TData, TErrorMap = Record<never, never>> =
  | {
      data: TData;
      error: undefined;
      response: Response;
    }
  | {
      data: undefined;
      error: ClientError<TErrorMap>;
      response: Response | undefined;
    };
