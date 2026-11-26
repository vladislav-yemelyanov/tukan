# Changelog

## 0.1.1

- Rewrite README with a concise quick start, Tukan logo, package badges, and support section.
- Add GitHub repository, homepage, and issue tracker metadata to `package.json`.

## 0.1.0

- Initial public release of `tukan`.
- Zero-dependency, schema-typed `fetch` HTTP client for Tukan-generated TypeScript OpenAPI types (`Schemas` / `Schemas["Operations"]`).
- Non-throwing `ClientResult<TData, TErrorMap>` contract with 7-category discriminated `ClientError<TErrorMap>` union and `error.is(status)` narrowing.
- Support for path/query/header/cookie serialization, JSON/multipart/urlencoded/text/binary payloads, streaming/blob downloads, `onRequest`/`onResponse`/`onError` hooks, timeouts, and `AbortSignal` cancellation.
