import 'package:tukan/tukan.dart';

const String defaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:4000',
);

TukanClient createApiClient({
  String baseUrl = defaultApiBaseUrl,
  required HttpTransport transport,
}) =>
    TukanClient(
      TukanClientConfig(
        baseUrl: baseUrl,
        transport: transport,
        timeout: const Duration(seconds: 10),
      ),
    );
