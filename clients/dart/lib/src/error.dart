import 'cancel_token.dart';
import 'transport.dart';

/// Client phase in which an [UnexpectedClientError] occurred.
enum ClientErrorStage {
  requestBuild,
  hook,
  internal,
}

/// Categorized error returned inside [ApiFailure] for all [TukanClient] failures.
sealed class ApiError<E> implements Exception {
  const ApiError();

  String get message;

  RawHttpResponse? get response => null;

  int? get status => response?.statusCode;

  /// Decoded contract error payload when this failure is an [ApiResponseError].
  E? get body => null;

  /// Raw parsed body (or response text) captured before/instead of contract decoding.
  Object? get rawBody => null;

  Object? get cause => null;

  StackTrace? get stackTrace => null;

  bool isStatus(int code) => status == code;

  /// Returns [body] (or [rawBody] fallback) cast to [U] if it matches [U] and optional HTTP [code].
  U? bodyAs<U>([int? code]) {
    if (code != null && status != code) return null;
    final Object? typed = body;
    if (typed is U) return typed;
    final Object? raw = rawBody;
    return raw is U ? raw : null;
  }

  bool get isNetworkError => this is NetworkError<E>;

  bool get isTimeout => this is TimeoutError<E>;

  bool get isCancelled => this is CancelledError<E>;

  @override
  String toString() => 'ApiError($message)';
}

/// Expected HTTP non-2xx error whose body matched and decoded into [E].
final class ApiResponseError<E> extends ApiError<E> {
  @override
  final String message;

  @override
  final int status;

  @override
  final E body;

  @override
  final RawHttpResponse response;

  @override
  final Object? rawBody;

  const ApiResponseError(
    this.message, {
    required this.status,
    required this.body,
    required this.response,
    this.rawBody,
  });
}

/// Unexpected HTTP non-2xx response (undeclared status, empty body, malformed JSON, or error decoder failure).
final class UnexpectedHttpError<E> extends ApiError<E> {
  @override
  final String message;

  @override
  final int status;

  @override
  final RawHttpResponse response;

  @override
  final Object? rawBody;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  const UnexpectedHttpError(
    this.message, {
    required this.status,
    required this.response,
    this.rawBody,
    this.cause,
    this.stackTrace,
  });
}

/// Transport/socket/DNS/TLS failure before receiving a valid HTTP response.
final class NetworkError<E> extends ApiError<E> {
  @override
  final String message;

  @override
  final Object cause;

  @override
  final StackTrace stackTrace;

  const NetworkError(
    this.message, {
    required this.cause,
    required this.stackTrace,
  });
}

/// Request exceeded its configured [timeout].
final class TimeoutError<E> extends ApiError<E> {
  @override
  final String message;

  final Duration? timeout;

  @override
  final Object cause;

  @override
  final StackTrace stackTrace;

  const TimeoutError(
    this.message, {
    this.timeout,
    required this.cause,
    required this.stackTrace,
  });
}

/// Request was cancelled via [CancelToken].
final class CancelledError<E> extends ApiError<E> {
  @override
  final String message;

  final Object? reason;

  @override
  final Object cause;

  @override
  final StackTrace stackTrace;

  const CancelledError(
    this.message, {
    this.reason,
    required this.cause,
    required this.stackTrace,
  });
}

/// Server returned 2xx, but JSON parsing or success model decoding failed (contract drift).
final class DecodeError<E> extends ApiError<E> {
  @override
  final String message;

  @override
  final int status;

  @override
  final RawHttpResponse response;

  @override
  final Object? rawBody;

  @override
  final Object cause;

  @override
  final StackTrace stackTrace;

  const DecodeError(
    this.message, {
    required this.status,
    required this.response,
    this.rawBody,
    required this.cause,
    required this.stackTrace,
  });
}

/// Client-side failure during request building, hooks, or internal client/transport bugs.
final class UnexpectedClientError<E> extends ApiError<E> {
  @override
  final String message;

  final ClientErrorStage stage;

  @override
  final RawHttpResponse? response;

  @override
  final Object cause;

  @override
  final StackTrace stackTrace;

  const UnexpectedClientError(
    this.message, {
    required this.stage,
    this.response,
    required this.cause,
    required this.stackTrace,
  });
}

/// Discriminated union returned by all [TukanClient] operations instead of throwing.
sealed class ApiResult<T, E> {
  const ApiResult();

  T? get data;

  ApiError<E>? get error;

  RawHttpResponse? get response;

  bool get isOk => this is ApiSuccess<T, E>;

  bool get isError => this is ApiFailure<T, E>;
}

final class ApiSuccess<T, E> extends ApiResult<T, E> {
  @override
  final T data;

  @override
  final RawHttpResponse response;

  const ApiSuccess(this.data, this.response);

  @override
  ApiError<E>? get error => null;
}

final class ApiFailure<T, E> extends ApiResult<T, E> {
  @override
  final ApiError<E> error;

  @override
  final RawHttpResponse? response;

  const ApiFailure(this.error, [this.response]);

  @override
  T? get data => null;
}
