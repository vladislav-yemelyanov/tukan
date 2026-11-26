import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tukan/tukan.dart';
import 'package:tukan_flutter_example/generated/todos.dart' as todos_api;
import 'package:tukan_flutter_example/main.dart';
import 'package:tukan_flutter_example/services/services.dart';

void main() {
  test('Todos CRUD, validation errors, and sealed UpdateTodoError flow', () async {
    final List<Uri> requestedUris = <Uri>[];

    final HttpTransport transport = HttpTransport.fromHandler((RawHttpRequest request) {
      requestedUris.add(request.uri);

      if (request.uri.path == '/api/v1/todos' && request.method == HttpMethod.get) {
        return RawHttpResponse.json(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'id': 'todo_01',
              'title': 'Verify Flutter Todo service',
              'status': 'todo',
              'priority': 'high',
              'createdAt': '2026-11-24T10:00:00.000Z',
              'updatedAt': '2026-11-24T10:00:00.000Z',
            },
          ],
          'page': 1,
          'pageSize': 25,
          'total': 1,
        });
      }

      if (request.uri.path == '/api/v1/todos' && request.method == HttpMethod.post) {
        final Map<String, Object?> body =
            jsonDecode(utf8.decode(request.body!)) as Map<String, Object?>;
        final String title = (body['title'] as String?) ?? '';
        if (title.length < 3) {
          return RawHttpResponse.json(
            <String, Object?>{
              'code': 'validation_error',
              'message': 'Validation failed',
              'fieldErrors': <String, String>{
                'title': 'Title must be at least 3 characters.',
              },
            },
            statusCode: 400,
          );
        }

        return RawHttpResponse.json(
          <String, Object?>{
            'id': 'todo_02',
            'title': title,
            'status': 'todo',
            'priority': body['priority'] ?? 'medium',
            'createdAt': '2026-11-24T10:02:00.000Z',
            'updatedAt': '2026-11-24T10:02:00.000Z',
          },
          statusCode: 201,
        );
      }

      if (request.uri.path == '/api/v1/todos/todo_01' && request.method == HttpMethod.get) {
        return RawHttpResponse.json(<String, Object?>{
          'id': 'todo_01',
          'title': 'Verify Flutter Todo service',
          'status': 'todo',
          'priority': 'high',
          'createdAt': '2026-11-24T10:00:00.000Z',
          'updatedAt': '2026-11-24T10:00:00.000Z',
        });
      }

      if (request.uri.path == '/api/v1/todos/todo_01' && request.method == HttpMethod.patch) {
        final Map<String, Object?> patchBody =
            jsonDecode(utf8.decode(request.body!)) as Map<String, Object?>;
        expect(patchBody['title'], 'Updated todo title');
        expect(patchBody['status'], 'done');
        expect(patchBody.containsKey('description'), isFalse);

        return RawHttpResponse.json(<String, Object?>{
          'id': 'todo_01',
          'title': patchBody['title'],
          'status': patchBody['status'],
          'priority': patchBody['priority'] ?? 'high',
          'createdAt': '2026-11-24T10:00:00.000Z',
          'updatedAt': '2026-11-24T10:05:00.000Z',
        });
      }

      if (request.uri.path == '/api/v1/todos/missing' && request.method == HttpMethod.patch) {
        return RawHttpResponse.json(
          <String, Object?>{'code': 'todo_not_found', 'message': 'Todo "missing" was not found.'},
          statusCode: 404,
        );
      }

      if (request.uri.path == '/api/v1/todos/todo_01' && request.method == HttpMethod.delete) {
        return RawHttpResponse.empty(statusCode: 204);
      }

      return RawHttpResponse.json(
        <String, Object?>{'code': 'not_found', 'message': 'Unexpected route'},
        statusCode: 404,
      );
    });

    final AppServices appServices = AppServices.create(
      baseUrl: 'https://example.test',
      transport: transport,
    );
    addTearDown(appServices.dispose);

    final listResult = await appServices.todos.list(
      status: TodoStatus.todo,
      priority: TodoPriority.high,
      search: 'Flutter',
    );
    expect(listResult, isA<ApiSuccess<TodoListResponse, Never>>());
    expect((listResult as ApiSuccess<TodoListResponse, Never>).data.items.single.id, 'todo_01');
    expect(
      requestedUris.first.queryParameters,
      <String, String>{'status': 'todo', 'priority': 'high', 'search': 'Flutter'},
    );

    final createdResult = await appServices.todos.create(
      title: 'Ship Todos example',
      priority: TodoPriority.high,
    );
    expect(createdResult, isA<ApiSuccess<Todo, todos_api.ValidationErrorResponse>>());
    expect((createdResult as ApiSuccess<Todo, todos_api.ValidationErrorResponse>).data.id, 'todo_02');

    final invalidCreate = await appServices.todos.create(title: 'a');
    expect(invalidCreate, isA<ApiFailure<Todo, todos_api.ValidationErrorResponse>>());
    expect(invalidCreate.error, isA<ApiResponseError<todos_api.ValidationErrorResponse>>());
    expect(
      invalidCreate.error?.body?.fieldErrors['title'],
      'Title must be at least 3 characters.',
    );

    final byIdResult = await appServices.todos.getById('todo_01');
    expect(byIdResult, isA<ApiSuccess<Todo, todos_api.ApiErrorResponse>>());
    expect(
      (byIdResult as ApiSuccess<Todo, todos_api.ApiErrorResponse>).data.title,
      'Verify Flutter Todo service',
    );

    final inferredById = await appServices.todos.client.send(
      todos_api.Paths.api.v1.todos.byTodoId('todo_01').get.request,
    );
    final Todo? inferredTodo = inferredById.data;
    expect(inferredTodo?.id, 'todo_01');

    final updateResult = await appServices.todos.update(
      'todo_01',
      title: 'Updated todo title',
      status: TodoStatus.done,
    );
    expect(updateResult, isA<ApiSuccess<Todo, todos_api.UpdateTodoError>>());
    expect((updateResult as ApiSuccess<Todo, todos_api.UpdateTodoError>).data.status, TodoStatus.done);

    final missingUpdate = await appServices.todos.update('missing', title: 'Valid title');
    expect(missingUpdate, isA<ApiFailure<Todo, todos_api.UpdateTodoError>>());
    expect(
      missingUpdate.error?.body?.apiErrorResponse?.message,
      'Todo "missing" was not found.',
    );

    final deleteResult = await appServices.todos.remove('todo_01');
    expect(deleteResult.isOk, isTrue);
  });

  testWidgets('TukanExampleApp renders Todos section and initial todo', (WidgetTester tester) async {
    final HttpTransport transport = HttpTransport.fromHandler((RawHttpRequest request) {
      if (request.uri.path == '/api/v1/todos' && request.method == HttpMethod.get) {
        return RawHttpResponse.json(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'id': 'todo_01',
              'title': 'Initial Flutter Todo',
              'status': 'todo',
              'priority': 'medium',
              'createdAt': '2026-11-24T10:00:00.000Z',
              'updatedAt': '2026-11-24T10:00:00.000Z',
            },
          ],
          'page': 1,
          'pageSize': 25,
          'total': 1,
        });
      }
      return RawHttpResponse.empty(statusCode: 404);
    });
    final AppServices appServices = AppServices.create(
      baseUrl: 'https://example.test',
      transport: transport,
    );
    addTearDown(appServices.dispose);

    await tester.pumpWidget(TukanExampleApp(appServices: appServices));
    await tester.pumpAndSettle();

    expect(find.text('Tukan + Flutter Todo Example'), findsOneWidget);
    expect(find.text('Todos (1)'), findsOneWidget);
    expect(find.text('Initial Flutter Todo'), findsOneWidget);
  });
}
