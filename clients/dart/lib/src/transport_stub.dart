import 'transport.dart';

HttpTransport createDefaultTransport({
  bool followRedirects = true,
  int maxRedirects = 5,
  bool persistentConnection = true,
}) {
  throw UnsupportedError(
    'Default dart:io HttpTransport is unavailable on this platform. '
    'Pass a custom HttpTransport via TukanClientConfig.transport.',
  );
}
