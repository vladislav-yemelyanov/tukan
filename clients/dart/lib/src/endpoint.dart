import 'decoders.dart';

enum HttpMethod {
  get,
  post,
  put,
  patch,
  delete,
  head,
  options,
  trace;

  String get wireName => name.toUpperCase();
}

/// Declarative endpoint descriptor pairing a Tukan response decoder with an HTTP method and path.
final class ApiEndpoint<T> {
  final HttpMethod method;
  final String path;
  final JsonFactory<T>? fromJson;
  final ResponseDecoder<T>? decode;
  final String? contentType;
  final Map<int, JsonFactory<Object?>>? errorFromJson;
  final Map<int, ResponseDecoder<Object?>>? errorDecoders;
  final ResponseDecoder<Object?>? defaultErrorDecoder;

  const ApiEndpoint({
    required this.method,
    required this.path,
    this.fromJson,
    this.decode,
    this.contentType,
    this.errorFromJson,
    this.errorDecoders,
    this.defaultErrorDecoder,
  });
}
