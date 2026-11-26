import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'cancel_token.dart';
import 'endpoint.dart';
import 'headers.dart';
import 'transport.dart';

Object _cancellationCause(Object? reason) {
  if (reason is TimeoutException || reason is ApiCancelledException) {
    return reason!;
  }
  return ApiCancelledException(reason);
}

/// Default `dart:io` [HttpClient]-backed transport for Dart VM, CLI, server, and Flutter native apps.
final class IoHttpTransport implements HttpTransport {
  final HttpClient? _externalClient;
  HttpClient? _ownedClient;
  final bool followRedirects;
  final int maxRedirects;
  final bool persistentConnection;

  IoHttpTransport({
    HttpClient? httpClient,
    this.followRedirects = true,
    this.maxRedirects = 5,
    this.persistentConnection = true,
  }) : _externalClient = httpClient;

  HttpClient get _client => _externalClient ?? (_ownedClient ??= HttpClient());

  @override
  Future<RawHttpResponse> send(RawHttpRequest request) async {
    final CancelToken? cancelToken = request.cancelToken;
    if (cancelToken != null && cancelToken.isCancelled) {
      throw _cancellationCause(cancelToken.reason);
    }

    final HttpClientRequest ioRequest =
        await _client.openUrl(request.method.wireName, request.uri);
    ioRequest.followRedirects = request.followRedirects ?? followRedirects;
    ioRequest.maxRedirects = request.maxRedirects ?? maxRedirects;
    ioRequest.persistentConnection = request.persistentConnection ?? persistentConnection;

    void Function()? unsubscribe;
    if (cancelToken != null) {
      unsubscribe = cancelToken.addListener((Object? reason) {
        ioRequest.abort(_cancellationCause(reason));
      });
    }

    try {
      for (final MapEntry<String, String> entry in request.headers.entries) {
        ioRequest.headers.set(entry.key, entry.value);
      }

      final Uint8List? body = request.body;
      if (body != null) {
        ioRequest.contentLength = body.length;
        ioRequest.add(body);
      }

      final HttpClientResponse ioResponse = await ioRequest.close();

      final Uint8List bodyBytes;
      if (request.method == HttpMethod.head) {
        await ioResponse.drain<void>();
        bodyBytes = Uint8List(0);
      } else {
        final BytesBuilder builder = BytesBuilder(copy: false);
        await for (final List<int> chunk in ioResponse) {
          builder.add(chunk);
        }
        bodyBytes = builder.takeBytes();
      }

      final HttpHeadersMap responseHeaders = HttpHeadersMap();
      ioResponse.headers.forEach((String name, List<String> values) {
        responseHeaders.set(name, values.join(', '));
      });

      return RawHttpResponse(
        statusCode: ioResponse.statusCode,
        reasonPhrase: ioResponse.reasonPhrase,
        headers: responseHeaders,
        bodyBytes: bodyBytes,
      );
    } finally {
      unsubscribe?.call();
    }
  }

  @override
  void close({bool force = false}) {
    _ownedClient?.close(force: force);
    _ownedClient = null;
  }
}

HttpTransport createDefaultTransport({
  bool followRedirects = true,
  int maxRedirects = 5,
  bool persistentConnection = true,
}) =>
    IoHttpTransport(
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      persistentConnection: persistentConnection,
    );
