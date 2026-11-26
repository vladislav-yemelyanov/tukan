/// Structural Dart 3 record matching `OperationRequest<T, E>` emitted by Tukan in `api.dart`.
typedef TukanOperation<T, E> = ({
  String method,
  String path,
  Map<String, dynamic>? pathParams,
  Map<String, dynamic>? query,
  Map<String, dynamic>? headers,
  Map<String, dynamic>? cookie,
  Object? body,
  String? contentType,
  T Function(Object? data) decodeResponse,
  Map<int, E Function(Object? data)?> errorDecoders,
  E Function(Object? data)? defaultErrorDecoder,
});
