import type { ClientError, ClientResult, ErrorMapBody } from "./error.js";

export type HttpMethod =
  | "get"
  | "post"
  | "put"
  | "patch"
  | "delete"
  | "head"
  | "options"
  | "trace";

/**
 * Extracts `Schemas["Operations"]` when a full `Schemas` interface is passed,
 * or keeps a raw operations map (including `Schemas["Operations_"]`).
 */
export type ExtractOperations<TSchema> =
  TSchema extends { Operations: infer TOperations }
    ? keyof TOperations extends `/${string}`
      ? TOperations
      : TSchema
    : TSchema;

export type OperationPath<TOps> = Extract<keyof TOps, string>;

export type PathMethods<TOps, TPath extends OperationPath<TOps>> = Extract<
  keyof TOps[TPath],
  HttpMethod
>;

type IsKeyRequired<T, K extends PropertyKey> = K extends keyof T
  ? {} extends Pick<T, K>
    ? false
    : true
  : false;

type AllowUndefinedOptional<T> = {
  [K in keyof T]: {} extends Pick<T, K> ? T[K] | undefined : T[K];
};

type NormalizeParamSlice<TSourceKey extends PropertyKey, TValue> = TSourceKey extends
  | "query"
  | "cookie"
  ? TValue extends Record<string, unknown>
    ? AllowUndefinedOptional<TValue>
    : TValue
  : TValue;

type ParametersOf<TOp> = TOp extends { parameters: infer TParams } ? TParams : {};

type OptionSlice<TMap, TSourceKey extends PropertyKey, TTargetKey extends string> =
  TSourceKey extends keyof TMap
    ? IsKeyRequired<TMap, TSourceKey> extends true
      ? { [K in TTargetKey]: NormalizeParamSlice<TSourceKey, Exclude<TMap[TSourceKey], undefined>> }
      : {
          [K in TTargetKey]?:
            | NormalizeParamSlice<TSourceKey, Exclude<TMap[TSourceKey], undefined>>
            | undefined;
        }
    : {};

export type HeaderValue =
  | string
  | number
  | boolean
  | readonly (string | number | boolean | null | undefined)[]
  | null
  | undefined;

export type ExtraHeaders = Record<string, HeaderValue>;

type HeaderParamOption<TParams> = "header" extends keyof TParams
  ? IsKeyRequired<TParams, "header"> extends true
    ? { headers: AllowUndefinedOptional<Exclude<TParams["header"], undefined>> & ExtraHeaders }
    : {
        headers?:
          | (AllowUndefinedOptional<Exclude<TParams["header"], undefined>> & ExtraHeaders)
          | HeadersInit
          | undefined;
      }
  : { headers?: HeadersInit | ExtraHeaders | undefined };

type RequestBodyMap<TOp> = "requestBody" extends keyof TOp
  ? Exclude<TOp["requestBody"], undefined>
  : never;

type MediaBodyVariants<
  TBodyMap,
  TMedia extends Extract<keyof TBodyMap, string> = Extract<keyof TBodyMap, string>,
> = TMedia extends "application/json"
  ? {
      contentType?: "application/json" | undefined;
      body: TBodyMap[TMedia];
    }
  : {
      contentType: TMedia;
      body: TBodyMap[TMedia];
    };

type BodyField<TBodyMap, TRequired extends boolean> = [TBodyMap] extends [never]
  ? {}
  : keyof TBodyMap extends never
    ? {}
    : TRequired extends true
      ? MediaBodyVariants<TBodyMap>
      : MediaBodyVariants<TBodyMap> | { contentType?: undefined; body?: undefined };

export type FetchRequestOptions = Omit<RequestInit, "method" | "headers" | "body" | "signal">;

export type RequestOptions<TOp> = {
  signal?: AbortSignal | undefined;
  timeoutMs?: number | undefined;
  requestInit?: FetchRequestOptions | undefined;
  extra?: Record<string, unknown> | undefined;
} & OptionSlice<ParametersOf<TOp>, "path", "path"> &
  OptionSlice<ParametersOf<TOp>, "query", "query"> &
  HeaderParamOption<ParametersOf<TOp>> &
  OptionSlice<ParametersOf<TOp>, "cookie", "cookie"> &
  BodyField<RequestBodyMap<TOp>, IsKeyRequired<TOp, "requestBody">>;

type ResponsesOf<TOp> = TOp extends { responses: infer TResponses } ? TResponses : {};

type SuccessStatusKey<TResponses> = Extract<keyof TResponses, `2${string}`>;

type ErrorStatusKey<TResponses> = Extract<
  keyof TResponses,
  `4${string}` | `5${string}` | "default"
>;

type MediaPayload<TMediaMap> = keyof TMediaMap extends never
  ? undefined
  : TMediaMap[keyof TMediaMap];

export type SuccessData<TOp> = [SuccessStatusKey<ResponsesOf<TOp>>] extends [never]
  ? undefined
  : {
      [K in SuccessStatusKey<ResponsesOf<TOp>>]: MediaPayload<ResponsesOf<TOp>[K]>;
    }[SuccessStatusKey<ResponsesOf<TOp>>];

type NormalizeErrorStatusKey<K> = K extends `${infer TCode extends number}` ? TCode : K;

export type ErrorMap<TOp> = {
  [K in ErrorStatusKey<ResponsesOf<TOp>> as NormalizeErrorStatusKey<K>]: MediaPayload<
    ResponsesOf<TOp>[K]
  >;
};

export type ErrorBody<TOp> = ErrorMapBody<ErrorMap<TOp>>;

export type OperationResult<TOp> = ClientResult<SuccessData<TOp>, ErrorMap<TOp>>;

export type MethodCall<TOp> = {} extends RequestOptions<TOp>
  ? (options?: RequestOptions<TOp>) => Promise<OperationResult<TOp>>
  : (options: RequestOptions<TOp>) => Promise<OperationResult<TOp>>;

export type PathClient<TOps, TPath extends OperationPath<TOps>> = {
  [TMethod in PathMethods<TOps, TPath>]: MethodCall<TOps[TPath][TMethod]>;
};

export interface Client<TOps> {
  path<TPath extends OperationPath<TOps>>(path: TPath): PathClient<TOps, TPath>;
}

export interface HeadersContext {
  readonly method: HttpMethod;
  readonly path: string;
  readonly url: string;
}

export type HeadersProvider =
  | HeadersInit
  | ExtraHeaders
  | ((
      context: HeadersContext,
    ) =>
      | HeadersInit
      | ExtraHeaders
      | undefined
      | Promise<HeadersInit | ExtraHeaders | undefined>);

export interface RequestContext {
  readonly method: HttpMethod;
  readonly path: string;
  url: string;
  readonly headers: Headers;
  readonly init: RequestInit;
  readonly extra: Record<string, unknown>;
}

export type OnRequestHook = (context: RequestContext) => void | Promise<void>;

export type OnResponseHook = (
  context: Readonly<RequestContext>,
  response: Response,
) => Response | void | Promise<Response | void>;

export type OnErrorHook = (
  context: Readonly<RequestContext>,
  error: ClientError,
) => void | Promise<void>;

export interface ClientConfig {
  baseUrl: string;
  headers?: HeadersProvider | undefined;
  fetch?: typeof fetch | undefined;
  requestInit?: FetchRequestOptions | undefined;
  timeoutMs?: number | undefined;
  onRequest?: OnRequestHook | readonly OnRequestHook[] | undefined;
  onResponse?: OnResponseHook | readonly OnResponseHook[] | undefined;
  onError?: OnErrorHook | readonly OnErrorHook[] | undefined;
}
