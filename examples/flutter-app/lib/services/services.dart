import 'package:tukan/tukan.dart';

import 'api_config.dart';
import 'todos_service.dart';

export '../generated/todos.dart'
    show Todo, TodoListResponse, TodoPriority, TodoStatus;
export 'todos_service.dart';

final class AppServices {
  final TodosService todos;
  final HttpTransport _transport;

  AppServices._(this.todos, this._transport);

  factory AppServices.create({
    String baseUrl = defaultApiBaseUrl,
    HttpTransport? transport,
  }) {
    final HttpTransport resolvedTransport = transport ?? IoHttpTransport();
    final TukanClient client = createApiClient(
      baseUrl: baseUrl,
      transport: resolvedTransport,
    );

    return AppServices._(
      TodosService(client: client),
      resolvedTransport,
    );
  }

  void dispose({bool force = false}) {
    final HttpTransport currentTransport = _transport;
    if (currentTransport is IoHttpTransport) {
      currentTransport.close(force: force);
    } else {
      currentTransport.close();
    }
  }
}

final AppServices services = AppServices.create();
