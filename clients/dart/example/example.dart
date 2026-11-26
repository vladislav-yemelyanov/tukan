import 'package:tukan/tukan.dart';

Future<void> main() async {
  final TukanClient client = TukanClient(
    const TukanClientConfig(
      baseUrl: 'https://api.example.com',
      timeout: Duration(seconds: 10),
    ),
  );

  // Generated `Paths` files produce an `OperationRequest<T, E>` record matching `TukanOperation<T, E>`.
  final TukanOperation<String, Never> healthCheck = (
    method: 'GET',
    path: '/health',
    pathParams: null,
    query: null,
    headers: null,
    cookie: null,
    body: null,
    contentType: null,
    decodeResponse: (Object? data) => data.toString(),
    errorDecoders: const <int, Never Function(Object?)?>{},
    defaultErrorDecoder: null,
  );

  try {
    final ApiResult<String, Never> result = await client.send(healthCheck);

    switch (result) {
      case ApiSuccess<String, Never>(:final data, :final response):
        print('OK (${response.statusCode}): $data');
      case ApiFailure<String, Never>(:final error):
        switch (error) {
          case ApiResponseError<Never>(:final status, :final message):
            print('API error $status: $message');
          case UnexpectedHttpError<Never>(:final status, :final message):
            print('Unexpected HTTP $status: $message');
          case NetworkError<Never>(:final message):
            print('Network failure: $message');
          case TimeoutError<Never>(:final message):
            print('Timed out: $message');
          case CancelledError<Never>(:final message):
            print('Cancelled: $message');
          case DecodeError<Never>(:final message):
            print('Decode failure: $message');
          case UnexpectedClientError<Never>(:final stage, :final message):
            print('Client error (${stage.name}): $message');
        }
    }
  } finally {
    client.close();
  }
}
