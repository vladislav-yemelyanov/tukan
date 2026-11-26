# Tukan HTTP Client Requirements

Shared behavioral contract for all companion HTTP clients generated or maintained alongside Tukan (currently TypeScript `tukan` in [clients/ts](../clients/ts/README.md) and Dart `tukan` in [clients/dart](../clients/dart/README.md), plus any future language clients).

All Tukan clients share three foundational constraints:

- **Zero external runtime dependencies:** Built purely on platform/standard-library primitives (Web Fetch APIs in TypeScript, `dart:io` / standard library in Dart).
- **Zero-import boundary in generated files:** Generated `api.ts` and `api.dart` contain no HTTP client imports or transport code. TypeScript emits structural `Schemas` / `Operations` types; Dart emits zero-import `OperationRequest<T, E>` records matching `TukanOperation<T, E>`.
- **Strict non-throwing call contract:** Every request resolves to a typed result union (`ClientResult` / `ApiResult`) and classifies all transport, build, decode, timeout, cancellation, and hook failures into a uniform 7-category error model.

---

## Requirements Matrix

| ID | Area | Requirement | TypeScript (`tukan`) | Dart (`tukan`) |
|---|---|---|---|---|
| `R1` | Non-throwing Result Contract | Every call resolves to a typed success/failure union; missing params, network failures, decode errors, and throwing hooks never escape uncaught. | `Promise<ClientResult<TData, TErrorMap>>` (`data` vs `error` + `response`). | `Future<ApiResult<T, E>>` (`ApiSuccess<T, E>` / `ApiFailure<T, E>`). |
| `R2` | Typed Operations & Error Narrowing | Compile-time route, HTTP method, required/optional params, request body, success type, and error narrowing without manual consumer casts. | `client.path("/...")` + `error.is(status)` per-status type guard. | `client.send(Paths...request)` + `ApiResult<T, E>` + sealed `<Op>Error` unions (`Never` when 0 error models). |
| `R3` | URL, Path & Query Serialization | Trim trailing slashes on `baseUrl` (`""` and relative `"/proxy/"` supported), URI-encode `{param}` path substitutions, fail on missing `{param}` as `request_build` without calling transport, omit `null`/`undefined`, repeat array query keys, format `Date`/`DateTime` as ISO-8601, JSON-serialize nested objects. | `buildUrl` + `toSearchParams` -> `UnexpectedClientError(stage: "request_build")`. | `buildRequestUri` + `encodeSearchParams` -> `UnexpectedClientError(stage: ClientErrorStage.requestBuild)`. |
| `R4` | Headers & Cookies Precedence | Case-insensitive, non-mutating header merge (`static base` < `headersProvider` < `operation` < `per-call`), array header joining with `", "` (omitting nulls), URL-encoded `cookie` formatting appending to any existing `Cookie` header. | `buildHeaders` merges `Headers` without mutating inputs. | `HttpHeadersMap` + `buildRequestHeaders` merges case-insensitively without mutating inputs. |
| `R5` | Request Bodies & File Uploads | Support JSON (`application/json`, `*+json`), `application/x-www-form-urlencoded`, `text/*`, raw binary (`application/octet-stream`), and `multipart/form-data` (files with filename/MIME, multi-file arrays, mixed scalar/JSON fields, null omission, safe boundary `Content-Type` handling). `Content-Type` precedence: `per-call header` > `contentType` param > `base header` > `application/json`. Invalid/unserializable body fails at `request_build`. | `serializeBody` (`FormData`, `Blob`, `File`, `URLSearchParams`, `Uint8Array`, JSON) strips manual multipart header so `fetch` attaches boundary. | `serializeRequestBody` + `encodeMultipart` (`MultipartBody`, `MultipartFile`, `Uint8List`/`List<int>`) escapes disposition values and sets boundary header. |
| `R6` | Response Parsing & Downloads | `HEAD`, `204`, `205`, `304`, `Content-Length: 0`, and whitespace-only JSON return empty (`undefined` / `null`). Parse JSON (`application/json`, `*+json`), decode `text/*` and empty MIME as UTF-8 `string`, and return binary payloads (`application/octet-stream`, `image/*`, `application/pdf`, etc.) as native binary types. | `parseResponseBody` returns `undefined`, parsed JSON, `string`, or `Blob`. | `_parseResponseBody` returns `null`, `jsonDecode`, `String`, or `Uint8List`. |
| `R7` | 7-Category Error Matrix | Classify all failures into 7 variants: `ApiResponseError` (`response`), `UnexpectedHttpError` (`unexpected_http`), `NetworkError` (`network`), `TimeoutError` (`timeout`), `CancelledError` (`cancelled`), `DecodeError` (`decode`), and `UnexpectedClientError` (`client`, with `stage`: `request_build` \| `hook` \| `internal`), preserving `status`, `response`, `body`, `rawBody`, `cause` (plus `stackTrace` in Dart). | `ClientError<TMap>` discriminated union (`err.kind`) extending `abstract class ApiError<TMap>`. | `sealed class ApiError<E>` with 7 `final class` subtypes (`ClientErrorStage`). |
| `R8` | Lifecycle & Hooks | Ordered pipeline: URL build -> `headersProvider` -> headers/body build -> `onRequest` list -> transport -> `onResponse` list -> parse/decode -> `onError` list. Chained `onRequest` hooks can add/override/delete headers, rewrite URL, update body/options, and share per-request state via shallow-copied `context.extra`. Chained `onResponse` hooks can replace responses. Throwing hooks become `UnexpectedClientError(stage: hook)`. | `onRequest`, `onResponse`, `onError` arrays/callbacks; `context.extra` shallow-copied from `options.extra`. | `headersProvider`, `onRequest`, `onResponse`, `onError` lists; `context.extra` copied from `extra:`. |
| `R9` | Retries & Single-Flight Refresh | Support bounded HTTP status retries (`429`/`503`) in `onResponse` via `context.extra`, concurrent single-flight `401` token refresh + replay with refreshed `Authorization` and retry-once guard (`_retried`), and transport-level retry wrappers for transient `NetworkError`. | `onResponse` hook + `fetch` wrapper; `context.extra` tracks attempt count / `_retried`. | `onResponse` hook + `HttpTransport` wrapper; `context.extra` tracks attempt count / `_retried`. |
| `R10` | Cancellation & Timeouts | Support pre-cancelled and mid-flight cancellation preserving custom `reason`; support client-wide and per-request timeouts (including `<= 0` immediate timeout). Compose signal + timeout so whichever triggers first wins, with pre-cancelled user signal taking precedence over `timeout <= 0`. | `AbortSignal` + `timeoutMs` via `createRequestSignal`. | `CancelToken` + `Duration timeout` via `_createRequestSignal` and `_sendWithCancellation`. |
| `R11` | Pluggable Transport & Lifecycle | Injectable transport (`fetch` / `HttpTransport`) for testing, SSR proxies, or custom adapters. Default runtime transport must preserve `globalThis.fetch` receiver binding (TS) and support real HTTP sockets, cancellation abort, and `client.close()` transport-ownership rules (Dart). | `ClientConfig.fetch` + default wrapper binding `globalThis.fetch`. | `TukanClientConfig.transport` + `IoHttpTransport`; `client.close()` closes only owned transports. |

---

## Intentional Platform Differences

- **Compile-time vs. runtime error decoding:** TypeScript erases `Schemas` at runtime, so any cleanly parsed non-2xx payload maps to `ApiResponseError` (narrowed via `error.is(status)`) while malformed non-2xx JSON maps to `UnexpectedHttpError`. Dart receives runtime `errorDecoders` / `defaultErrorDecoder` in `OperationRequest<T, E>` (and optional `config.errorFromJson`), so undeclared statuses, missing/mismatched decoders, and `E = Never` responses route to `UnexpectedHttpError<E>` preserving `rawBody`.
- **Route ergonomics:** TypeScript uses `client.path("/template").method(...)` directly against `Schemas["Operations"]`. Dart uses generated immutable typestate builders under `Paths` ending in `.request` (alongside manual `client.get`/`post` and `client.path(...)` helpers).
- **Resource disposal:** TypeScript's Web `fetch` requires no client `close()` method. Dart's `TukanClient.close()` closes the default `IoHttpTransport` when owned by the client and leaves externally provided `HttpTransport` instances open.

---

## Verification

Run each client's verification suite from the repository root:

```sh
bash scripts/check-ts-client.sh
bash scripts/check-dart-client.sh
```
