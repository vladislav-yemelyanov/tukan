import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'cancel_token.dart';
import 'endpoint.dart';
import 'headers.dart';

/// Low-level HTTP request passed to [HttpTransport.send].
final class RawHttpRequest {
  final HttpMethod method;
  final Uri uri;
  final HttpHeadersMap headers;
  final Uint8List? body;
  final CancelToken? cancelToken;
  final bool? followRedirects;
  final int? maxRedirects;
  final bool? persistentConnection;
  final Map<String, Object?> extra;

  const RawHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
    this.cancelToken,
    this.followRedirects,
    this.maxRedirects,
    this.persistentConnection,
    this.extra = const <String, Object?>{},
  });
}

/// Low-level HTTP response returned by [HttpTransport.send].
final class RawHttpResponse {
  final int statusCode;
  final String reasonPhrase;
  final HttpHeadersMap headers;
  final Uint8List bodyBytes;

  const RawHttpResponse({
    required this.statusCode,
    this.reasonPhrase = '',
    required this.headers,
    required this.bodyBytes,
  });

  factory RawHttpResponse.json(
    Object? value, {
    int statusCode = 200,
    String reasonPhrase = 'OK',
    Map<String, String>? headers,
  }) {
    final HttpHeadersMap resolvedHeaders = HttpHeadersMap(headers);
    if (!resolvedHeaders.containsKey('content-type')) {
      resolvedHeaders.set('content-type', 'application/json');
    }
    return RawHttpResponse(
      statusCode: statusCode,
      reasonPhrase: reasonPhrase,
      headers: resolvedHeaders,
      bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(value))),
    );
  }

  factory RawHttpResponse.text(
    String text, {
    int statusCode = 200,
    String reasonPhrase = 'OK',
    String contentType = 'text/plain; charset=utf-8',
    Map<String, String>? headers,
  }) {
    final HttpHeadersMap resolvedHeaders = HttpHeadersMap(headers);
    if (!resolvedHeaders.containsKey('content-type')) {
      resolvedHeaders.set('content-type', contentType);
    }
    return RawHttpResponse(
      statusCode: statusCode,
      reasonPhrase: reasonPhrase,
      headers: resolvedHeaders,
      bodyBytes: Uint8List.fromList(utf8.encode(text)),
    );
  }

  factory RawHttpResponse.empty({
    int statusCode = 204,
    String reasonPhrase = 'No Content',
    Map<String, String>? headers,
  }) =>
      RawHttpResponse(
        statusCode: statusCode,
        reasonPhrase: reasonPhrase,
        headers: HttpHeadersMap(headers),
        bodyBytes: Uint8List(0),
      );

  bool get isOk => statusCode >= 200 && statusCode < 300;

  String get bodyText => utf8.decode(bodyBytes, allowMalformed: true);
}

typedef HttpTransportHandler = FutureOr<RawHttpResponse> Function(RawHttpRequest request);

/// Pluggable transport abstraction (defaults to `dart:io` [IoHttpTransport] on VM/mobile/desktop).
abstract interface class HttpTransport {
  factory HttpTransport.fromHandler(
    HttpTransportHandler handler, {
    void Function()? onClose,
  }) = _HandlerHttpTransport;

  Future<RawHttpResponse> send(RawHttpRequest request);

  void close();
}

final class _HandlerHttpTransport implements HttpTransport {
  final HttpTransportHandler _handler;
  final void Function()? _onClose;

  _HandlerHttpTransport(this._handler, {void Function()? onClose}) : _onClose = onClose;

  @override
  Future<RawHttpResponse> send(RawHttpRequest request) async => await _handler(request);

  @override
  void close() {
    _onClose?.call();
  }
}
