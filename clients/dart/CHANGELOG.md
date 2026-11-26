# Changelog

## 0.1.1

- Rewrite README with a concise quick start, Tukan logo, package badges, and support section.
- Add GitHub repository, homepage, and issue tracker metadata to `pubspec.yaml`.

## 0.1.0

- Initial public release of `tukan`.
- Zero-dependency, `dart:io`-native typed HTTP client for Tukan-generated Dart OpenAPI models and `Paths` operation trees.
- Strict non-throwing `ApiResult<T, E>` (`ApiSuccess` / `ApiFailure`) contract with a 7-subtype `sealed class ApiError<E>` hierarchy.
- Support for path/query/header/cookie serialization, JSON/multipart/urlencoded/text/binary payloads, `onRequest`/`onResponse`/`onError` hooks, `CancelToken`, timeouts, and pluggable `HttpTransport`.
