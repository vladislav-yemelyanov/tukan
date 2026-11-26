// Generated from OpenAPI schemas; defaults not applied.

// ignore: unused_element
const Object _unset = Object();

// ignore: unused_element
bool _deepEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEqual(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

// ignore: unused_element
int _deepHash(Object? value) {
  if (value is List) return Object.hashAll(value.map(_deepHash));
  if (value is Map) return Object.hashAllUnordered(value.entries.map((entry) => Object.hash(entry.key, _deepHash(entry.value))));
  return value.hashCode;
}

// ignore: unused_element
Object? _requiredJson(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw FormatException('Missing required property: $key');
  return json[key];
}

// Schema: "ApiErrorResponse"
class ApiErrorResponse {
  final String code;
  final String? details;
  final String message;

  const ApiErrorResponse({
    required this.code,
    this.details,
    required this.message,
  });

  factory ApiErrorResponse.fromJson(Map<String, dynamic> json) => ApiErrorResponse(
    code: _requiredJson(json, "code") as String,
    details: json["details"] as String?,
    message: _requiredJson(json, "message") as String,
  );

  Map<String, dynamic> toJson() => {
    "code": this.code,
    if (this.details != null) "details": this.details,
    "message": this.message,
  };

  ApiErrorResponse copyWith({
    String? code,
    Object? details = _unset,
    String? message,
  }) => ApiErrorResponse(
    code: code ?? this.code,
    details: identical(details, _unset) ? this.details : details as String?,
    message: message ?? this.message,
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is ApiErrorResponse && other.runtimeType == runtimeType && this.code == other.code && this.details == other.details && this.message == other.message;

  @override
  int get hashCode => Object.hash(runtimeType, this.code, this.details, this.message);
}

// Schema: "CreateTodoRequest"
class CreateTodoRequest {
  final String? description;
  final TodoPriority? priority;
  /// minLength: 3
  final String title;

  const CreateTodoRequest({
    this.description,
    this.priority,
    required this.title,
  });

  factory CreateTodoRequest.fromJson(Map<String, dynamic> json) => CreateTodoRequest(
    description: json["description"] as String?,
    priority: (json["priority"] == null ? null : TodoPriority.fromJson(json["priority"])),
    title: _requiredJson(json, "title") as String,
  );

  Map<String, dynamic> toJson() => {
    if (this.description != null) "description": this.description,
    if (this.priority case final _v0?) "priority": _v0.value,
    "title": this.title,
  };

  CreateTodoRequest copyWith({
    Object? description = _unset,
    Object? priority = _unset,
    String? title,
  }) => CreateTodoRequest(
    description: identical(description, _unset) ? this.description : description as String?,
    priority: identical(priority, _unset) ? this.priority : priority as TodoPriority?,
    title: title ?? this.title,
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is CreateTodoRequest && other.runtimeType == runtimeType && this.description == other.description && this.priority == other.priority && this.title == other.title;

  @override
  int get hashCode => Object.hash(runtimeType, this.description, this.priority, this.title);
}

/// DELETE /api/v1/todos/{todoId}
/// Delete a todo
// Schema: "DeleteTodoPathParameters"
class DeleteTodoPathParameters {
  final String todoId;

  const DeleteTodoPathParameters({
    required this.todoId,
  });

  factory DeleteTodoPathParameters.fromJson(Map<String, dynamic> json) => DeleteTodoPathParameters(
    todoId: _requiredJson(json, "todoId") as String,
  );

  Map<String, dynamic> toJson() => {
    "todoId": this.todoId,
  };

  DeleteTodoPathParameters copyWith({
    String? todoId,
  }) => DeleteTodoPathParameters(
    todoId: todoId ?? this.todoId,
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is DeleteTodoPathParameters && other.runtimeType == runtimeType && this.todoId == other.todoId;

  @override
  int get hashCode => Object.hash(runtimeType, this.todoId);
}

/// GET /api/v1/todos/{todoId}
/// Get a single todo by ID
// Schema: "GetTodoPathParameters"
class GetTodoPathParameters {
  final String todoId;

  const GetTodoPathParameters({
    required this.todoId,
  });

  factory GetTodoPathParameters.fromJson(Map<String, dynamic> json) => GetTodoPathParameters(
    todoId: _requiredJson(json, "todoId") as String,
  );

  Map<String, dynamic> toJson() => {
    "todoId": this.todoId,
  };

  GetTodoPathParameters copyWith({
    String? todoId,
  }) => GetTodoPathParameters(
    todoId: todoId ?? this.todoId,
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is GetTodoPathParameters && other.runtimeType == runtimeType && this.todoId == other.todoId;

  @override
  int get hashCode => Object.hash(runtimeType, this.todoId);
}

/// GET /api/v1/todos
/// List todos with optional filtering and pagination
// Schema: "ListTodosQueryParameters"
class ListTodosQueryParameters {
  /// minimum: 1
  final int? page;
  /// maximum: 100
  /// minimum: 1
  final int? pageSize;
  final TodoPriority? priority;
  final String? search;
  final TodoStatus? status;

  const ListTodosQueryParameters({
    this.page,
    this.pageSize,
    this.priority,
    this.search,
    this.status,
  });

  factory ListTodosQueryParameters.fromJson(Map<String, dynamic> json) => ListTodosQueryParameters(
    page: json["page"] as int?,
    pageSize: json["pageSize"] as int?,
    priority: (json["priority"] == null ? null : TodoPriority.fromJson(json["priority"])),
    search: json["search"] as String?,
    status: (json["status"] == null ? null : TodoStatus.fromJson(json["status"])),
  );

  Map<String, dynamic> toJson() => {
    if (this.page != null) "page": this.page,
    if (this.pageSize != null) "pageSize": this.pageSize,
    if (this.priority case final _v0?) "priority": _v0.value,
    if (this.search != null) "search": this.search,
    if (this.status case final _v0?) "status": _v0.value,
  };

  ListTodosQueryParameters copyWith({
    Object? page = _unset,
    Object? pageSize = _unset,
    Object? priority = _unset,
    Object? search = _unset,
    Object? status = _unset,
  }) => ListTodosQueryParameters(
    page: identical(page, _unset) ? this.page : page as int?,
    pageSize: identical(pageSize, _unset) ? this.pageSize : pageSize as int?,
    priority: identical(priority, _unset) ? this.priority : priority as TodoPriority?,
    search: identical(search, _unset) ? this.search : search as String?,
    status: identical(status, _unset) ? this.status : status as TodoStatus?,
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is ListTodosQueryParameters && other.runtimeType == runtimeType && this.page == other.page && this.pageSize == other.pageSize && this.priority == other.priority && this.search == other.search && this.status == other.status;

  @override
  int get hashCode => Object.hash(runtimeType, this.page, this.pageSize, this.priority, this.search, this.status);
}

// Schema: "Todo"
class Todo {
  final String createdAt;
  final String? description;
  final String id;
  final TodoPriority priority;
  final TodoStatus status;
  final String title;
  final String updatedAt;

  const Todo({
    required this.createdAt,
    this.description,
    required this.id,
    required this.priority,
    required this.status,
    required this.title,
    required this.updatedAt,
  });

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
    createdAt: _requiredJson(json, "createdAt") as String,
    description: json["description"] as String?,
    id: _requiredJson(json, "id") as String,
    priority: TodoPriority.fromJson(_requiredJson(json, "priority")),
    status: TodoStatus.fromJson(_requiredJson(json, "status")),
    title: _requiredJson(json, "title") as String,
    updatedAt: _requiredJson(json, "updatedAt") as String,
  );

  Map<String, dynamic> toJson() => {
    "createdAt": this.createdAt,
    if (this.description != null) "description": this.description,
    "id": this.id,
    "priority": this.priority.value,
    "status": this.status.value,
    "title": this.title,
    "updatedAt": this.updatedAt,
  };

  Todo copyWith({
    String? createdAt,
    Object? description = _unset,
    String? id,
    TodoPriority? priority,
    TodoStatus? status,
    String? title,
    String? updatedAt,
  }) => Todo(
    createdAt: createdAt ?? this.createdAt,
    description: identical(description, _unset) ? this.description : description as String?,
    id: id ?? this.id,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is Todo && other.runtimeType == runtimeType && this.createdAt == other.createdAt && this.description == other.description && this.id == other.id && this.priority == other.priority && this.status == other.status && this.title == other.title && this.updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(runtimeType, this.createdAt, this.description, this.id, this.priority, this.status, this.title, this.updatedAt);
}

// Schema: "TodoListResponse"
class TodoListResponse {
  final List<Todo> items;
  final int page;
  final int pageSize;
  final int total;

  const TodoListResponse({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  factory TodoListResponse.fromJson(Map<String, dynamic> json) => TodoListResponse(
    items: (_requiredJson(json, "items") as List).map((item) => Todo.fromJson(Map<String, dynamic>.from(item as Map))).toList(),
    page: _requiredJson(json, "page") as int,
    pageSize: _requiredJson(json, "pageSize") as int,
    total: _requiredJson(json, "total") as int,
  );

  Map<String, dynamic> toJson() => {
    "items": this.items.map((item) => item.toJson()).toList(),
    "page": this.page,
    "pageSize": this.pageSize,
    "total": this.total,
  };

  TodoListResponse copyWith({
    List<Todo>? items,
    int? page,
    int? pageSize,
    int? total,
  }) => TodoListResponse(
    items: items ?? this.items,
    page: page ?? this.page,
    pageSize: pageSize ?? this.pageSize,
    total: total ?? this.total,
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is TodoListResponse && other.runtimeType == runtimeType && _deepEqual(this.items, other.items) && this.page == other.page && this.pageSize == other.pageSize && this.total == other.total;

  @override
  int get hashCode => Object.hash(runtimeType, _deepHash(this.items), this.page, this.pageSize, this.total);
}

// Schema: "TodoPriority"
enum TodoPriority {
  low("low"),
  medium("medium"),
  high("high");

  final String value;
  const TodoPriority(this.value);
  static TodoPriority fromJson(Object? json) => values.firstWhere((item) => _deepEqual(item.value, json), orElse: () => throw FormatException('Invalid enum value: $json'));
  Object? toJson() => value;
}

// Schema: "TodoStatus"
enum TodoStatus {
  todo("todo"),
  inProgress("in_progress"),
  done("done");

  final String value;
  const TodoStatus(this.value);
  static TodoStatus fromJson(Object? json) => values.firstWhere((item) => _deepEqual(item.value, json), orElse: () => throw FormatException('Invalid enum value: $json'));
  Object? toJson() => value;
}

/// PATCH /api/v1/todos/{todoId}
/// Update todo fields
// Schema: "UpdateTodoPathParameters"
class UpdateTodoPathParameters {
  final String todoId;

  const UpdateTodoPathParameters({
    required this.todoId,
  });

  factory UpdateTodoPathParameters.fromJson(Map<String, dynamic> json) => UpdateTodoPathParameters(
    todoId: _requiredJson(json, "todoId") as String,
  );

  Map<String, dynamic> toJson() => {
    "todoId": this.todoId,
  };

  UpdateTodoPathParameters copyWith({
    String? todoId,
  }) => UpdateTodoPathParameters(
    todoId: todoId ?? this.todoId,
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateTodoPathParameters && other.runtimeType == runtimeType && this.todoId == other.todoId;

  @override
  int get hashCode => Object.hash(runtimeType, this.todoId);
}

// Schema: "UpdateTodoRequest"
class UpdateTodoRequest {
  final String? description;
  final TodoPriority? priority;
  final TodoStatus? status;
  /// minLength: 3
  final String? title;

  const UpdateTodoRequest({
    this.description,
    this.priority,
    this.status,
    this.title,
  });

  factory UpdateTodoRequest.fromJson(Map<String, dynamic> json) => UpdateTodoRequest(
    description: json["description"] as String?,
    priority: (json["priority"] == null ? null : TodoPriority.fromJson(json["priority"])),
    status: (json["status"] == null ? null : TodoStatus.fromJson(json["status"])),
    title: json["title"] as String?,
  );

  Map<String, dynamic> toJson() => {
    if (this.description != null) "description": this.description,
    if (this.priority case final _v0?) "priority": _v0.value,
    if (this.status case final _v0?) "status": _v0.value,
    if (this.title != null) "title": this.title,
  };

  UpdateTodoRequest copyWith({
    Object? description = _unset,
    Object? priority = _unset,
    Object? status = _unset,
    Object? title = _unset,
  }) => UpdateTodoRequest(
    description: identical(description, _unset) ? this.description : description as String?,
    priority: identical(priority, _unset) ? this.priority : priority as TodoPriority?,
    status: identical(status, _unset) ? this.status : status as TodoStatus?,
    title: identical(title, _unset) ? this.title : title as String?,
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateTodoRequest && other.runtimeType == runtimeType && this.description == other.description && this.priority == other.priority && this.status == other.status && this.title == other.title;

  @override
  int get hashCode => Object.hash(runtimeType, this.description, this.priority, this.status, this.title);
}

// Schema: "ValidationErrorResponse"
class ValidationErrorResponse {
  final String code;
  final Map<String, String> fieldErrors;
  final String message;

  const ValidationErrorResponse({
    required this.code,
    required this.fieldErrors,
    required this.message,
  });

  factory ValidationErrorResponse.fromJson(Map<String, dynamic> json) => ValidationErrorResponse(
    code: _requiredJson(json, "code") as String,
    fieldErrors: (_requiredJson(json, "fieldErrors") as Map).map((key, value) => MapEntry(key as String, value as String)),
    message: _requiredJson(json, "message") as String,
  );

  Map<String, dynamic> toJson() => {
    "code": this.code,
    "fieldErrors": this.fieldErrors.map((key, value) => MapEntry(key, value)),
    "message": this.message,
  };

  ValidationErrorResponse copyWith({
    String? code,
    Map<String, String>? fieldErrors,
    String? message,
  }) => ValidationErrorResponse(
    code: code ?? this.code,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    message: message ?? this.message,
  );

  @override
  bool operator ==(Object other) => identical(this, other) || other is ValidationErrorResponse && other.runtimeType == runtimeType && this.code == other.code && _deepEqual(this.fieldErrors, other.fieldErrors) && this.message == other.message;

  @override
  int get hashCode => Object.hash(runtimeType, this.code, _deepHash(this.fieldErrors), this.message);
}

typedef OperationRequest<T, E> = ({
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

abstract final class Paths {
  static const PathApi api = PathApi._();
}

final class PathApi {
  const PathApi._();
  PathApiV1 get v1 => const PathApiV1._();
}

final class PathApiV1 {
  const PathApiV1._();
  PathApiV1Todos get todos => const PathApiV1Todos._();
}

final class PathApiV1Todos {
  const PathApiV1Todos._();
  String get path => "/api/v1/todos";
  PathApiV1TodosByTodoId get byTodoId => const PathApiV1TodosByTodoId._();
  /// GET /api/v1/todos
  /// List todos with optional filtering and pagination
  PathApiV1TodosGet get get => const PathApiV1TodosGet._();
  /// POST /api/v1/todos
  /// Create a new todo
  PathApiV1TodosPost get post => const PathApiV1TodosPost._();
}

/// GET /api/v1/todos
/// List todos with optional filtering and pagination
final class PathApiV1TodosGet {
  final Map<String, dynamic>? _query;
  const PathApiV1TodosGet._({Map<String, dynamic>? query}) : _query = query;
  String get method => 'GET';
  String get path => "/api/v1/todos";

  PathApiV1TodosGet query({
    int? page,
    int? pageSize,
    TodoPriority? priority,
    String? search,
    TodoStatus? status,
  }) => PathApiV1TodosGet._(query: ListTodosQueryParameters(page: page, pageSize: pageSize, priority: priority, search: search, status: status).toJson());

  PathApiV1TodosGet withQuery(ListTodosQueryParameters? value) => PathApiV1TodosGet._(query: value?.toJson());

  OperationRequest<TodoListResponse, Never> get request => (
    method: 'GET',
    path: "/api/v1/todos",
    pathParams: null,
    query: _query,
    headers: null,
    cookie: null,
    body: null,
    contentType: null,
    decodeResponse: (Object? data) => TodoListResponse.fromJson(Map<String, dynamic>.from(data as Map)),
    errorDecoders: const <int, Never Function(Object? data)?>{},
    defaultErrorDecoder: null,
  );
}

/// POST /api/v1/todos
/// Create a new todo
final class PathApiV1TodosPost {
  const PathApiV1TodosPost._();
  String get method => 'POST';
  String get path => "/api/v1/todos";

  PathApiV1TodosPostReady body({
    String? description,
    TodoPriority? priority,
    required String title,
  }) => PathApiV1TodosPostReady._(body: CreateTodoRequest(description: description, priority: priority, title: title));

  PathApiV1TodosPostReady withBody(CreateTodoRequest value) => PathApiV1TodosPostReady._(body: value);
}

final class PathApiV1TodosPostReady {
  final Object? _body;
  const PathApiV1TodosPostReady._({required Object? body}) : _body = body;
  String get method => 'POST';
  String get path => "/api/v1/todos";

  PathApiV1TodosPostReady body({
    String? description,
    TodoPriority? priority,
    required String title,
  }) => PathApiV1TodosPostReady._(body: CreateTodoRequest(description: description, priority: priority, title: title));

  PathApiV1TodosPostReady withBody(CreateTodoRequest value) => PathApiV1TodosPostReady._(body: value);

  OperationRequest<Todo, ValidationErrorResponse> get request => (
    method: 'POST',
    path: "/api/v1/todos",
    pathParams: null,
    query: null,
    headers: null,
    cookie: null,
    body: _body,
    contentType: "application/json",
    decodeResponse: (Object? data) => Todo.fromJson(Map<String, dynamic>.from(data as Map)),
    errorDecoders: <int, ValidationErrorResponse Function(Object? data)?>{
      400: (Object? data) => ValidationErrorResponse.fromJson(Map<String, dynamic>.from(data as Map)),
    },
    defaultErrorDecoder: null,
  );
}

final class PathApiV1TodosByTodoId {
  const PathApiV1TodosByTodoId._();
  String get path => "/api/v1/todos/{todoId}";
  PathApiV1TodosByTodoIdBound call(String todoId) => PathApiV1TodosByTodoIdBound._(todoId);
}

final class PathApiV1TodosByTodoIdBound {
  final String _todoId;
  const PathApiV1TodosByTodoIdBound._(this._todoId);
  String get path => "/api/v1/todos/{todoId}";
  /// DELETE /api/v1/todos/{todoId}
  /// Delete a todo
  PathApiV1TodosByTodoIdDelete get delete => PathApiV1TodosByTodoIdDelete._(_todoId);
  /// GET /api/v1/todos/{todoId}
  /// Get a single todo by ID
  PathApiV1TodosByTodoIdGet get get => PathApiV1TodosByTodoIdGet._(_todoId);
  /// PATCH /api/v1/todos/{todoId}
  /// Update todo fields
  PathApiV1TodosByTodoIdPatch get patch => PathApiV1TodosByTodoIdPatch._(_todoId);
}

/// DELETE /api/v1/todos/{todoId}
/// Delete a todo
final class PathApiV1TodosByTodoIdDelete {
  final String _todoId;
  const PathApiV1TodosByTodoIdDelete._(this._todoId);
  String get method => 'DELETE';
  String get path => "/api/v1/todos/{todoId}";

  OperationRequest<void, ApiErrorResponse> get request => (
    method: 'DELETE',
    path: "/api/v1/todos/{todoId}",
    pathParams: <String, dynamic>{"todoId": _todoId},
    query: null,
    headers: null,
    cookie: null,
    body: null,
    contentType: null,
    decodeResponse: (Object? _) {},
    errorDecoders: <int, ApiErrorResponse Function(Object? data)?>{
      404: (Object? data) => ApiErrorResponse.fromJson(Map<String, dynamic>.from(data as Map)),
    },
    defaultErrorDecoder: null,
  );
}

/// GET /api/v1/todos/{todoId}
/// Get a single todo by ID
final class PathApiV1TodosByTodoIdGet {
  final String _todoId;
  const PathApiV1TodosByTodoIdGet._(this._todoId);
  String get method => 'GET';
  String get path => "/api/v1/todos/{todoId}";

  OperationRequest<Todo, ApiErrorResponse> get request => (
    method: 'GET',
    path: "/api/v1/todos/{todoId}",
    pathParams: <String, dynamic>{"todoId": _todoId},
    query: null,
    headers: null,
    cookie: null,
    body: null,
    contentType: null,
    decodeResponse: (Object? data) => Todo.fromJson(Map<String, dynamic>.from(data as Map)),
    errorDecoders: <int, ApiErrorResponse Function(Object? data)?>{
      404: (Object? data) => ApiErrorResponse.fromJson(Map<String, dynamic>.from(data as Map)),
    },
    defaultErrorDecoder: null,
  );
}

sealed class UpdateTodoError {
  const UpdateTodoError();
  ValidationErrorResponse? get validationErrorResponse => null;
  ApiErrorResponse? get apiErrorResponse => null;
}

final class UpdateTodoErrorValidationErrorResponse extends UpdateTodoError {
  final ValidationErrorResponse value;
  const UpdateTodoErrorValidationErrorResponse(this.value);

  @override
  ValidationErrorResponse get validationErrorResponse => value;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateTodoErrorValidationErrorResponse && other.runtimeType == runtimeType && _deepEqual(value, other.value);

  @override
  int get hashCode => Object.hash(runtimeType, _deepHash(value));
}

final class UpdateTodoErrorApiErrorResponse extends UpdateTodoError {
  final ApiErrorResponse value;
  const UpdateTodoErrorApiErrorResponse(this.value);

  @override
  ApiErrorResponse get apiErrorResponse => value;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UpdateTodoErrorApiErrorResponse && other.runtimeType == runtimeType && _deepEqual(value, other.value);

  @override
  int get hashCode => Object.hash(runtimeType, _deepHash(value));
}

/// PATCH /api/v1/todos/{todoId}
/// Update todo fields
final class PathApiV1TodosByTodoIdPatch {
  final String _todoId;
  const PathApiV1TodosByTodoIdPatch._(this._todoId);
  String get method => 'PATCH';
  String get path => "/api/v1/todos/{todoId}";

  PathApiV1TodosByTodoIdPatchReady body({
    String? description,
    TodoPriority? priority,
    TodoStatus? status,
    String? title,
  }) => PathApiV1TodosByTodoIdPatchReady._(_todoId, body: UpdateTodoRequest(description: description, priority: priority, status: status, title: title));

  PathApiV1TodosByTodoIdPatchReady withBody(UpdateTodoRequest value) => PathApiV1TodosByTodoIdPatchReady._(_todoId, body: value);
}

final class PathApiV1TodosByTodoIdPatchReady {
  final String _todoId;
  final Object? _body;
  const PathApiV1TodosByTodoIdPatchReady._(this._todoId, {required Object? body}) : _body = body;
  String get method => 'PATCH';
  String get path => "/api/v1/todos/{todoId}";

  PathApiV1TodosByTodoIdPatchReady body({
    String? description,
    TodoPriority? priority,
    TodoStatus? status,
    String? title,
  }) => PathApiV1TodosByTodoIdPatchReady._(_todoId, body: UpdateTodoRequest(description: description, priority: priority, status: status, title: title));

  PathApiV1TodosByTodoIdPatchReady withBody(UpdateTodoRequest value) => PathApiV1TodosByTodoIdPatchReady._(_todoId, body: value);

  OperationRequest<Todo, UpdateTodoError> get request => (
    method: 'PATCH',
    path: "/api/v1/todos/{todoId}",
    pathParams: <String, dynamic>{"todoId": _todoId},
    query: null,
    headers: null,
    cookie: null,
    body: _body,
    contentType: "application/json",
    decodeResponse: (Object? data) => Todo.fromJson(Map<String, dynamic>.from(data as Map)),
    errorDecoders: <int, UpdateTodoError Function(Object? data)?>{
      400: (Object? data) => UpdateTodoErrorValidationErrorResponse(ValidationErrorResponse.fromJson(Map<String, dynamic>.from(data as Map))),
      404: (Object? data) => UpdateTodoErrorApiErrorResponse(ApiErrorResponse.fromJson(Map<String, dynamic>.from(data as Map))),
    },
    defaultErrorDecoder: null,
  );
}

