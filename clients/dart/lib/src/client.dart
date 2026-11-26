import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'cancel_token.dart';
import 'decoders.dart';
import 'endpoint.dart';
import 'error.dart';
import 'headers.dart';
import 'operation.dart';
import 'serialization.dart';
import 'transport.dart';
import 'transport_default.dart';

final class HeadersContext {
  final HttpMethod method;
  final String path;
  final Uri uri;

  const HeadersContext({
    required this.method,
    required this.path,
    required this.uri,
  });
}

typedef HeadersProvider = FutureOr<Object?> Function(HeadersContext context);

final class RequestContext {
  final HttpMethod method;
  final String path;
  Uri uri;
  final HttpHeadersMap headers;
  Uint8List? body;
  final Map<String, Object?> extra;
  bool? followRedirects;
  int? maxRedirects;
  bool? persistentConnection;

  RequestContext({
    required this.method,
    required this.path,
    required this.uri,
    required this.headers,
    this.body,
    Map<String, Object?>? extra,
    this.followRedirects,
    this.maxRedirects,
    this.persistentConnection,
  }) : extra = extra ?? <String, Object?>{};
}

typedef OnRequestHook = FutureOr<void> Function(RequestContext context);
typedef OnResponseHook = FutureOr<RawHttpResponse?> Function(
  RequestContext context,
  RawHttpResponse response,
);
typedef OnErrorHook = FutureOr<void> Function(RequestContext context, ApiError<Object?> error);

final class TukanClientConfig {
  final String baseUrl;
  final Object? headers;
  final HeadersProvider? headersProvider;
  final HttpTransport? transport;
  final Duration? timeout;
  final bool followRedirects;
  final int maxRedirects;
  final bool persistentConnection;
  final Map<int, JsonFactory<Object?>>? errorFromJson;
  final Map<int, ResponseDecoder<Object?>>? errorDecoders;
  final ResponseDecoder<Object?>? defaultErrorDecoder;
  final List<OnRequestHook> onRequest;
  final List<OnResponseHook> onResponse;
  final List<OnErrorHook> onError;

  const TukanClientConfig({
    required this.baseUrl,
    this.headers,
    this.headersProvider,
    this.transport,
    this.timeout,
    this.followRedirects = true,
    this.maxRedirects = 5,
    this.persistentConnection = true,
    this.errorFromJson,
    this.errorDecoders,
    this.defaultErrorDecoder,
    this.onRequest = const <OnRequestHook>[],
    this.onResponse = const <OnResponseHook>[],
    this.onError = const <OnErrorHook>[],
  });
}

final class _RequestSignal {
  final CancelToken? token;
  final void Function() cleanup;

  const _RequestSignal(this.token, this.cleanup);
}

_RequestSignal _createRequestSignal(CancelToken? userToken, Duration? timeout) {
  if (timeout == null) {
    return _RequestSignal(userToken, () {});
  }

  final CancelToken linked = CancelToken();
  Timer? timer;
  void Function()? unsubscribe;

  if (userToken != null) {
    if (userToken.isCancelled) {
      linked.cancel(userToken.reason);
      return _RequestSignal(linked, () {});
    }
    unsubscribe = userToken.addListener((Object? reason) {
      timer?.cancel();
      linked.cancel(reason);
    });
  }

  if (timeout <= Duration.zero) {
    linked.cancel(TimeoutException('Request timed out', timeout));
    return _RequestSignal(linked, () => unsubscribe?.call());
  }

  timer = Timer(timeout, () {
    linked.cancel(TimeoutException('Request timed out after ${timeout.inMilliseconds}ms', timeout));
  });

  return _RequestSignal(linked, () {
    timer?.cancel();
    unsubscribe?.call();
  });
}

Object _cancellationCause(Object? reason) {
  if (reason is TimeoutException || reason is ApiCancelledException) {
    return reason!;
  }
  return ApiCancelledException(reason);
}

typedef _ParsedBodyResult = ({
  Object? parsed,
  bool parseFailed,
  String? rawText,
  Object? error,
  StackTrace? stackTrace,
});

String _httpErrorMessage(RawHttpResponse response) => response.reasonPhrase.isNotEmpty
    ? 'HTTP ${response.statusCode} ${response.reasonPhrase}'
    : 'HTTP ${response.statusCode}';

_ParsedBodyResult _parseResponseBody(RawHttpResponse response, HttpMethod method) {
  if (method == HttpMethod.head ||
      response.statusCode == 204 ||
      response.statusCode == 205 ||
      response.statusCode == 304 ||
      response.headers.get('content-length')?.trim() == '0' ||
      response.bodyBytes.isEmpty) {
    return (parsed: null, parseFailed: false, rawText: null, error: null, stackTrace: null);
  }

  final String mime = normalizeMimeType(response.headers.get('content-type') ?? '');

  if (isJsonMimeType(mime)) {
    String? decodedText;
    try {
      decodedText = utf8.decode(response.bodyBytes);
      if (decodedText.trim().isEmpty) {
        return (parsed: null, parseFailed: false, rawText: null, error: null, stackTrace: null);
      }
      return (
        parsed: jsonDecode(decodedText),
        parseFailed: false,
        rawText: decodedText,
        error: null,
        stackTrace: null,
      );
    } on FormatException catch (cause, stackTrace) {
      return (
        parsed: null,
        parseFailed: true,
        rawText: decodedText ?? utf8.decode(response.bodyBytes, allowMalformed: true),
        error: cause,
        stackTrace: stackTrace,
      );
    }
  }

  if (mime.isEmpty || mime.startsWith('text/')) {
    try {
      final String text = utf8.decode(response.bodyBytes);
      return (parsed: text, parseFailed: false, rawText: text, error: null, stackTrace: null);
    } on FormatException catch (cause, stackTrace) {
      return (
        parsed: null,
        parseFailed: true,
        rawText: utf8.decode(response.bodyBytes, allowMalformed: true),
        error: cause,
        stackTrace: stackTrace,
      );
    }
  }

  return (parsed: response.bodyBytes, parseFailed: false, rawText: null, error: null, stackTrace: null);
}

({bool matched, E? body, Object? rawBody, Object? decodeError, StackTrace? decodeStackTrace})
    _decodeErrorPayload<E>(
  RawHttpResponse response,
  Object? rawParsed, {
  Map<int, JsonFactory<Object?>>? configFromJson,
  Map<int, ResponseDecoder<Object?>>? configDecoders,
  ResponseDecoder<Object?>? configDefaultDecoder,
  Map<int, JsonFactory<Object?>>? requestFromJson,
  Map<int, ResponseDecoder<E>>? requestDecoders,
  ResponseDecoder<E>? requestDefaultDecoder,
}) {
  if (rawParsed == null) {
    return (matched: false, body: null, rawBody: null, decodeError: null, decodeStackTrace: null);
  }

  final int status = response.statusCode;
  final ResponseDecoder<Object?>? reqDecoder = requestDecoders?[status];
  final JsonFactory<Object?>? reqFactory = requestFromJson?[status];
  final ResponseDecoder<Object?>? cfgDecoder = configDecoders?[status];
  final JsonFactory<Object?>? cfgFactory = configFromJson?[status];
  final ResponseDecoder<Object?>? fallbackDecoder = requestDefaultDecoder ?? configDefaultDecoder;

  Object? decodeWithFactory(JsonFactory<Object?> factory) {
    if (rawParsed is! Map) {
      throw FormatException(
        'Expected JSON object for HTTP $status error body, got ${rawParsed.runtimeType}',
      );
    }
    return factory(Map<String, dynamic>.from(rawParsed));
  }

  try {
    final Object? decoded;
    if (reqDecoder != null) {
      decoded = reqDecoder(rawParsed);
    } else if (reqFactory != null) {
      decoded = decodeWithFactory(reqFactory);
    } else if (cfgDecoder != null) {
      decoded = cfgDecoder(rawParsed);
    } else if (cfgFactory != null) {
      decoded = decodeWithFactory(cfgFactory);
    } else if (fallbackDecoder != null) {
      decoded = fallbackDecoder(rawParsed);
    } else {
      return (
        matched: false,
        body: null,
        rawBody: rawParsed,
        decodeError: null,
        decodeStackTrace: null,
      );
    }

    if (decoded is E) {
      return (
        matched: true,
        body: decoded,
        rawBody: rawParsed,
        decodeError: null,
        decodeStackTrace: null,
      );
    }

    return (
      matched: false,
      body: null,
      rawBody: decoded,
      decodeError: null,
      decodeStackTrace: null,
    );
  } catch (error, stackTrace) {
    return (
      matched: false,
      body: null,
      rawBody: rawParsed,
      decodeError: error,
      decodeStackTrace: stackTrace,
    );
  }
}

({T? value, DecodeError<E>? error}) _decodeSuccessPayload<T, E>(
  Object? rawParsed,
  RawHttpResponse response,
  JsonFactory<T>? fromJson,
  ResponseDecoder<T>? decode,
) {
  try {
    if (decode != null) {
      return (value: decode(rawParsed), error: null);
    }

    if (fromJson != null) {
      if (rawParsed is! Map) {
        throw FormatException(
          'Expected JSON object for $T, got ${rawParsed.runtimeType}',
        );
      }
      return (value: fromJson(Map<String, dynamic>.from(rawParsed)), error: null);
    }

    if (rawParsed is T) {
      return (value: rawParsed, error: null);
    }

    throw FormatException(
      'Expected response payload of type $T, got ${rawParsed.runtimeType}',
    );
  } catch (cause, stackTrace) {
    return (
      value: null,
      error: DecodeError<E>(
        'Failed to decode HTTP ${response.statusCode} response into $T: $cause',
        status: response.statusCode,
        response: response,
        rawBody: rawParsed,
        cause: cause,
        stackTrace: stackTrace,
      ),
    );
  }
}

HttpMethod? _parseHttpMethod(String value) {
  final String normalized = value.trim().toLowerCase();
  for (final HttpMethod method in HttpMethod.values) {
    if (method.name == normalized) return method;
  }
  return null;
}

/// Typed, non-throwing HTTP client tailored for Tukan-generated Dart OpenAPI models.
final class TukanClient {
  final TukanClientConfig config;
  final HttpTransport _transport;
  final bool _ownsTransport;

  TukanClient(this.config)
      : _ownsTransport = config.transport == null,
        _transport = config.transport ??
            createDefaultTransport(
              followRedirects: config.followRedirects,
              maxRedirects: config.maxRedirects,
              persistentConnection: config.persistentConnection,
            );

  PathClient path(String template) => PathClient._(this, template);

  /// Executes a type-safe [TukanOperation] generated under `Paths` in Tukan's `api.dart`.
  Future<ApiResult<T, E>> send<T, E>(
    TukanOperation<T, E> operation, {
    Object? headers,
    Object? cookie,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) async {
    final HttpMethod? method = _parseHttpMethod(operation.method);
    if (method == null) {
      final UnexpectedClientError<E> buildError = UnexpectedClientError<E>(
        'Unsupported HTTP method "${operation.method}"',
        stage: ClientErrorStage.requestBuild,
        cause: ArgumentError.value(operation.method, 'method', 'Unsupported HTTP method'),
        stackTrace: StackTrace.current,
      );
      final RequestContext fallbackContext = RequestContext(
        method: HttpMethod.get,
        path: operation.path,
        uri: Uri.tryParse(operation.path) ?? Uri(),
        headers: HttpHeadersMap(),
      );
      return ApiFailure<T, E>(await _notifyErrorHooks<E>(fallbackContext, buildError));
    }

    final Object? mergedHeaders;
    final Object? mergedCookies;
    try {
      mergedHeaders = mergeHeaderOverrides(operation.headers, headers);
      mergedCookies = mergeParamOverrides(operation.cookie, cookie, 'cookie');
    } catch (err, stackTrace) {
      final UnexpectedClientError<E> buildError = UnexpectedClientError<E>(
        err.toString(),
        stage: ClientErrorStage.requestBuild,
        cause: err,
        stackTrace: stackTrace,
      );
      final RequestContext fallbackContext = RequestContext(
        method: method,
        path: operation.path,
        uri: Uri.tryParse(operation.path) ?? Uri(),
        headers: HttpHeadersMap(),
      );
      return ApiFailure<T, E>(await _notifyErrorHooks<E>(fallbackContext, buildError));
    }

    final Map<int, ResponseDecoder<E>> errorDecoders = <int, ResponseDecoder<E>>{};
    for (final MapEntry<int, E Function(Object? data)?> entry in operation.errorDecoders.entries) {
      final E Function(Object? data)? decoder = entry.value;
      if (decoder != null) {
        errorDecoders[entry.key] = decoder;
      }
    }

    return _execute<T, E>(
      method,
      operation.path,
      pathParams: operation.pathParams,
      query: operation.query,
      headers: mergedHeaders,
      cookie: mergedCookies,
      body: operation.body,
      contentType: operation.contentType,
      decode: operation.decodeResponse,
      errorDecoders: errorDecoders.isEmpty ? null : errorDecoders,
      defaultErrorDecoder: operation.defaultErrorDecoder,
      timeout: timeout,
      cancelToken: cancelToken,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      persistentConnection: persistentConnection,
      extra: extra,
    );
  }

  Future<ApiResult<T, Object?>> call<T>(
    ApiEndpoint<T> endpoint, {
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      request<T>(
        endpoint.method,
        endpoint.path,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType ?? endpoint.contentType,
        fromJson: endpoint.fromJson,
        decode: endpoint.decode,
        errorFromJson: errorFromJson ?? endpoint.errorFromJson,
        errorDecoders: errorDecoders ?? endpoint.errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder ?? endpoint.defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> get<T>(
    String path, {
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      request<T>(
        HttpMethod.get,
        path,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> post<T>(
    String path, {
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      request<T>(
        HttpMethod.post,
        path,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> put<T>(
    String path, {
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      request<T>(
        HttpMethod.put,
        path,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> patch<T>(
    String path, {
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      request<T>(
        HttpMethod.patch,
        path,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> delete<T>(
    String path, {
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      request<T>(
        HttpMethod.delete,
        path,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<void, Object?>> head(
    String path, {
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      request<void>(
        HttpMethod.head,
        path,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> options<T>(
    String path, {
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      request<T>(
        HttpMethod.options,
        path,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> request<T>(
    HttpMethod method,
    String path, {
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      _execute<T, Object?>(
        method,
        path,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, E>> _execute<T, E>(
    HttpMethod method,
    String path, {
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<E>>? errorDecoders,
    ResponseDecoder<E>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) async {
    RawHttpResponse? response;
    RequestContext? context;
    ClientErrorStage stage = ClientErrorStage.requestBuild;
    bool inTransport = false;
    final Duration? effectiveTimeout = timeout ?? config.timeout;
    final _RequestSignal signal = _createRequestSignal(cancelToken, effectiveTimeout);

    try {
      final Uri uri = buildRequestUri(
        config.baseUrl,
        path,
        pathParams: pathParams,
        query: query,
      );

      final Object? dynamicBaseHeaders;
      if (config.headersProvider == null) {
        dynamicBaseHeaders = null;
      } else {
        stage = ClientErrorStage.hook;
        dynamicBaseHeaders = await config.headersProvider!(
          HeadersContext(method: method, path: path, uri: uri),
        );
      }

      stage = ClientErrorStage.requestBuild;
      final ({HttpHeadersMap headers, bool hasRequestContentType}) resolvedHeaders =
          buildRequestHeaders(config.headers, dynamicBaseHeaders, headers, cookie);

      final Uint8List? serializedBody = serializeRequestBody(
        body,
        contentType,
        resolvedHeaders.headers,
        resolvedHeaders.hasRequestContentType,
      );

      context = RequestContext(
        method: method,
        path: path,
        uri: uri,
        headers: resolvedHeaders.headers,
        body: serializedBody,
        extra: extra == null ? <String, Object?>{} : Map<String, Object?>.of(extra),
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
      );

      stage = ClientErrorStage.hook;
      for (final OnRequestHook hook in config.onRequest) {
        await hook(context);
      }

      final RawHttpRequest rawRequest = RawHttpRequest(
        method: method,
        uri: context.uri,
        headers: context.headers,
        body: context.body,
        cancelToken: signal.token,
        followRedirects: context.followRedirects,
        maxRedirects: context.maxRedirects,
        persistentConnection: context.persistentConnection,
        extra: context.extra,
      );

      stage = ClientErrorStage.internal;
      inTransport = true;
      response = await _sendWithCancellation(rawRequest, signal.token);
      inTransport = false;

      stage = ClientErrorStage.hook;
      for (final OnResponseHook hook in config.onResponse) {
        final RawHttpResponse? replacement = await hook(context, response!);
        if (replacement != null) {
          response = replacement;
        }
      }

      stage = ClientErrorStage.internal;
      final RawHttpResponse finalResponse = response!;
      final _ParsedBodyResult parsedResult = _parseResponseBody(finalResponse, method);

      if (!finalResponse.isOk) {
        final ApiError<E> httpError;
        if (parsedResult.parseFailed) {
          httpError = UnexpectedHttpError<E>(
            _httpErrorMessage(finalResponse),
            status: finalResponse.statusCode,
            response: finalResponse,
            rawBody: parsedResult.rawText,
            cause: parsedResult.error,
            stackTrace: parsedResult.stackTrace,
          );
        } else {
          final ({
            bool matched,
            E? body,
            Object? rawBody,
            Object? decodeError,
            StackTrace? decodeStackTrace,
          }) decodedError = _decodeErrorPayload<E>(
            finalResponse,
            parsedResult.parsed,
            configFromJson: config.errorFromJson,
            configDecoders: config.errorDecoders,
            configDefaultDecoder: config.defaultErrorDecoder,
            requestFromJson: errorFromJson,
            requestDecoders: errorDecoders,
            requestDefaultDecoder: defaultErrorDecoder,
          );

          if (decodedError.matched) {
            httpError = ApiResponseError<E>(
              _httpErrorMessage(finalResponse),
              status: finalResponse.statusCode,
              body: decodedError.body as E,
              response: finalResponse,
              rawBody: decodedError.rawBody,
            );
          } else {
            httpError = UnexpectedHttpError<E>(
              _httpErrorMessage(finalResponse),
              status: finalResponse.statusCode,
              response: finalResponse,
              rawBody: decodedError.rawBody,
              cause: decodedError.decodeError,
              stackTrace: decodedError.decodeStackTrace,
            );
          }
        }
        final ApiError<E> finalError = await _notifyErrorHooks<E>(context, httpError);
        return ApiFailure<T, E>(finalError, finalResponse);
      }

      if (parsedResult.parseFailed) {
        final DecodeError<E> parseError = DecodeError<E>(
          'Failed to parse JSON response (HTTP ${finalResponse.statusCode})',
          status: finalResponse.statusCode,
          response: finalResponse,
          rawBody: parsedResult.rawText,
          cause: parsedResult.error!,
          stackTrace: parsedResult.stackTrace!,
        );
        final ApiError<E> finalError = await _notifyErrorHooks<E>(context, parseError);
        return ApiFailure<T, E>(finalError, finalResponse);
      }

      final ({T? value, DecodeError<E>? error}) decoded = _decodeSuccessPayload<T, E>(
        parsedResult.parsed,
        finalResponse,
        fromJson,
        decode,
      );
      if (decoded.error != null) {
        final ApiError<E> finalError = await _notifyErrorHooks<E>(context, decoded.error!);
        return ApiFailure<T, E>(finalError, finalResponse);
      }

      return ApiSuccess<T, E>(decoded.value as T, finalResponse);
    } catch (thrown, stackTrace) {
      final ApiError<E> apiError = _classifyThrown<E>(
        thrown,
        stackTrace,
        response: response,
        stage: stage,
        inTransport: inTransport,
        timeout: effectiveTimeout,
      );
      final RawHttpResponse? errorResponse = apiError.response ?? response;
      final RequestContext fallbackContext = context ??
          RequestContext(
            method: method,
            path: path,
            uri: Uri.tryParse(path) ?? Uri(),
            headers: HttpHeadersMap(),
          );
      final ApiError<E> finalError = await _notifyErrorHooks<E>(fallbackContext, apiError);
      return ApiFailure<T, E>(finalError, errorResponse);
    } finally {
      signal.cleanup();
    }
  }

  Future<RawHttpResponse> _sendWithCancellation(
    RawHttpRequest rawRequest,
    CancelToken? token,
  ) {
    if (token == null) {
      return _transport.send(rawRequest);
    }

    if (token.isCancelled) {
      return Future<RawHttpResponse>.error(_cancellationCause(token.reason));
    }

    final Completer<RawHttpResponse> completer = Completer<RawHttpResponse>();
    final void Function() unsubscribe = token.addListener((Object? reason) {
      if (!completer.isCompleted) {
        completer.completeError(_cancellationCause(reason));
      }
    });

    unawaited(
      _transport.send(rawRequest).then(
        (RawHttpResponse result) {
          unsubscribe();
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          unsubscribe();
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      ),
    );

    return completer.future;
  }

  ApiError<E> _classifyThrown<E>(
    Object thrown,
    StackTrace stackTrace, {
    required RawHttpResponse? response,
    required ClientErrorStage stage,
    required bool inTransport,
    required Duration? timeout,
  }) {
    if (thrown is ApiError<E>) return thrown;

    if (thrown is TimeoutException) {
      return TimeoutError<E>(
        thrown.message ?? 'Request timed out',
        timeout: thrown.duration ?? timeout,
        cause: thrown,
        stackTrace: stackTrace,
      );
    }

    if (thrown is ApiCancelledException) {
      return CancelledError<E>(
        thrown.toString(),
        reason: thrown.reason,
        cause: thrown,
        stackTrace: stackTrace,
      );
    }

    if (inTransport) {
      if (thrown is Error) {
        return UnexpectedClientError<E>(
          'Transport error: $thrown',
          stage: ClientErrorStage.internal,
          cause: thrown,
          stackTrace: stackTrace,
        );
      }
      return NetworkError<E>(
        'Network request failed: $thrown',
        cause: thrown,
        stackTrace: stackTrace,
      );
    }

    if (thrown is RequestBuildException) {
      return UnexpectedClientError<E>(
        thrown.message,
        stage: ClientErrorStage.requestBuild,
        cause: thrown,
        stackTrace: stackTrace,
      );
    }

    final String message = response != null
        ? 'Failed to process HTTP ${response.statusCode} response: $thrown'
        : 'Request failed: $thrown';

    return UnexpectedClientError<E>(
      message,
      stage: stage,
      response: response,
      cause: thrown,
      stackTrace: stackTrace,
    );
  }

  Future<ApiError<E>> _notifyErrorHooks<E>(RequestContext context, ApiError<E> error) async {
    try {
      for (final OnErrorHook hook in config.onError) {
        await hook(context, error);
      }
      return error;
    } catch (hookError, stackTrace) {
      return UnexpectedClientError<E>(
        'onError hook failed: $hookError',
        stage: ClientErrorStage.hook,
        response: error.response,
        cause: hookError,
        stackTrace: stackTrace,
      );
    }
  }

  void close() {
    if (_ownsTransport) {
      _transport.close();
    }
  }
}

/// Fluent path-scoped wrapper matching `client.path('/...')` ergonomics from `tukan`.
final class PathClient {
  final TukanClient _client;
  final String _template;

  const PathClient._(this._client, this._template);

  Future<ApiResult<T, Object?>> get<T>({
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      _client.get<T>(
        _template,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> post<T>({
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      _client.post<T>(
        _template,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> put<T>({
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      _client.put<T>(
        _template,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> patch<T>({
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      _client.patch<T>(
        _template,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> delete<T>({
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      _client.delete<T>(
        _template,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<void, Object?>> head({
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      _client.head(
        _template,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );

  Future<ApiResult<T, Object?>> options<T>({
    Object? pathParams,
    Object? query,
    Object? headers,
    Object? cookie,
    Object? body,
    String? contentType,
    JsonFactory<T>? fromJson,
    ResponseDecoder<T>? decode,
    Map<int, JsonFactory<Object?>>? errorFromJson,
    Map<int, ResponseDecoder<Object?>>? errorDecoders,
    ResponseDecoder<Object?>? defaultErrorDecoder,
    Duration? timeout,
    CancelToken? cancelToken,
    bool? followRedirects,
    int? maxRedirects,
    bool? persistentConnection,
    Map<String, Object?>? extra,
  }) =>
      _client.options<T>(
        _template,
        pathParams: pathParams,
        query: query,
        headers: headers,
        cookie: cookie,
        body: body,
        contentType: contentType,
        fromJson: fromJson,
        decode: decode,
        errorFromJson: errorFromJson,
        errorDecoders: errorDecoders,
        defaultErrorDecoder: defaultErrorDecoder,
        timeout: timeout,
        cancelToken: cancelToken,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        persistentConnection: persistentConnection,
        extra: extra,
      );
}
