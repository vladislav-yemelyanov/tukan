import 'package:tukan/tukan.dart';

import '../generated/todos.dart' as todos;

final class TodosService {
  static final _todos = todos.Paths.api.v1.todos;

  final TukanClient client;

  const TodosService({required this.client});

  Future<ApiResult<todos.TodoListResponse, Never>> list({
    todos.TodoStatus? status,
    todos.TodoPriority? priority,
    String? search,
    int? page,
    int? pageSize,
  }) =>
      client.send(
        _todos.get
            .query(
              status: status,
              priority: priority,
              search: search,
              page: page,
              pageSize: pageSize,
            )
            .request,
      );

  Future<ApiResult<todos.Todo, todos.ApiErrorResponse>> getById(String todoId) =>
      client.send(_todos.byTodoId(todoId).get.request);

  Future<ApiResult<todos.Todo, todos.ValidationErrorResponse>> create({
    required String title,
    String? description,
    todos.TodoPriority? priority,
  }) =>
      client.send(
        _todos.post
            .body(
              title: title,
              description: description,
              priority: priority,
            )
            .request,
      );

  Future<ApiResult<todos.Todo, todos.UpdateTodoError>> update(
    String todoId, {
    String? title,
    String? description,
    todos.TodoStatus? status,
    todos.TodoPriority? priority,
  }) =>
      client.send(
        _todos.byTodoId(todoId)
            .patch
            .body(
              title: title,
              description: description,
              status: status,
              priority: priority,
            )
            .request,
      );

  Future<ApiResult<void, todos.ApiErrorResponse>> remove(String todoId) =>
      client.send(_todos.byTodoId(todoId).delete.request);
}
