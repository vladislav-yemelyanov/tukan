import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/tukan.dart';

void expectTrue(bool condition, String message) {
  if (!condition) {
    throw AssertionError('Assertion failed: $message');
  }
}

void expectEqual<T>(T actual, T expected, String label) {
  if (actual != expected) {
    throw AssertionError('$label: expected <$expected>, got <$actual>');
  }
}

void expectDeepEqual(Object? actual, Object? expected, String label) {
  final String actualJson = jsonEncode(actual);
  final String expectedJson = jsonEncode(expected);
  if (actualJson != expectedJson) {
    throw AssertionError('$label: expected $expectedJson, got $actualJson');
  }
}

Object? _requiredJson(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required property: $key');
  }
  return json[key];
}

// Synthetic models matching exact Tukan `core/generators/dart.odin` output.

enum TransactionSubtype {
  card('card'),
  transfer('transfer');

  final String value;
  const TransactionSubtype(this.value);
  static TransactionSubtype fromJson(Object? json) => values.firstWhere(
        (TransactionSubtype item) => item.value == json,
        orElse: () => throw FormatException('Invalid enum value: $json'),
      );
  Object? toJson() => value;
}

final class UserModel {
  final String id;
  final String name;

  const UserModel({required this.id, required this.name});

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: _requiredJson(json, 'id') as String,
        name: _requiredJson(json, 'name') as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModel && other.runtimeType == runtimeType && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(runtimeType, id, name);
}

final class ProblemDetails {
  final String? title;
  final String? detail;
  final int? status;

  const ProblemDetails({this.title, this.detail, this.status});

  factory ProblemDetails.fromJson(Map<String, dynamic> json) => ProblemDetails(
        title: json['title'] as String?,
        detail: json['detail'] as String?,
        status: json['status'] as int?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (title != null) 'title': title,
        if (detail != null) 'detail': detail,
        if (status != null) 'status': status,
      };
}

final class GetUserPathParameters {
  final String id;

  const GetUserPathParameters({required this.id});

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id};
}

final class GetUserQueryParameters {
  final bool? expand;
  final int? limit;
  final List<String?>? tags;
  final TransactionSubtype? subtype;

  const GetUserQueryParameters({this.expand, this.limit, this.tags, this.subtype});

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (expand != null) 'expand': expand,
        if (limit != null) 'limit': limit,
        if (tags != null) 'tags': tags,
        if (subtype case final TransactionSubtype s?) 'subtype': s.value,
      };
}

final class GetUserHeaderParameters {
  final String xRequestId;
  final String? xTrace;

  const GetUserHeaderParameters({required this.xRequestId, this.xTrace});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'X-Request-Id': xRequestId,
        if (xTrace != null) 'X-Trace': xTrace,
      };
}

final class GetUserCookieParameters {
  final String? session;

  const GetUserCookieParameters({this.session});

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (session != null) 'session': session,
      };
}

final class PostFileUploadRequest {
  final String accountId;
  final String binId;
  final List<int> file;

  const PostFileUploadRequest({
    required this.accountId,
    required this.binId,
    required this.file,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'AccountId': accountId,
        'BinId': binId,
        'File': file,
      };
}

final class ConflictError {
  final String conflictId;

  const ConflictError({required this.conflictId});

  factory ConflictError.fromJson(Map<String, dynamic> json) =>
      ConflictError(conflictId: _requiredJson(json, 'conflictId') as String);
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
  static const PathUsers users = PathUsers._();
  static const PathUpload upload = PathUpload._();
  static const PathDefaultError defaultError = PathDefaultError._();
  static const PathOrders orders = PathOrders._();
}

final class PathUsers {
  const PathUsers._();
  PathUsersById get byId => const PathUsersById._();
}

final class PathUsersById {
  const PathUsersById._();
  String get path => '/users/{id}';
  PathUsersByIdBound call(String id) => PathUsersByIdBound._(id);
}

final class PathUsersByIdBound {
  final String _id;
  const PathUsersByIdBound._(this._id);
  String get path => '/users/{id}';
  PathUsersByIdGet get get => PathUsersByIdGet._(_id);
}

final class PathUsersByIdGet {
  final String _id;
  final Map<String, dynamic>? _query;
  final Map<String, dynamic>? _cookie;
  const PathUsersByIdGet._(
    this._id, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? cookie,
  })  : _query = query,
        _cookie = cookie;
  String get method => 'GET';
  String get path => '/users/{id}';

  PathUsersByIdGet query({
    bool? expand,
    int? limit,
    List<String?>? tags,
    TransactionSubtype? subtype,
  }) =>
      PathUsersByIdGet._(
        _id,
        query: GetUserQueryParameters(
          expand: expand,
          limit: limit,
          tags: tags,
          subtype: subtype,
        ).toJson(),
        cookie: _cookie,
      );

  PathUsersByIdGet withQuery(GetUserQueryParameters? value) => PathUsersByIdGet._(
        _id,
        query: value?.toJson(),
        cookie: _cookie,
      );

  PathUsersByIdGetReady headers({
    required String xRequestId,
    String? xTrace,
  }) =>
      PathUsersByIdGetReady._(
        _id,
        headers: GetUserHeaderParameters(
          xRequestId: xRequestId,
          xTrace: xTrace,
        ).toJson(),
        query: _query,
        cookie: _cookie,
      );

  PathUsersByIdGetReady withHeaders(GetUserHeaderParameters value) =>
      PathUsersByIdGetReady._(
        _id,
        headers: value.toJson(),
        query: _query,
        cookie: _cookie,
      );

  PathUsersByIdGet cookie({
    String? session,
  }) =>
      PathUsersByIdGet._(
        _id,
        query: _query,
        cookie: GetUserCookieParameters(session: session).toJson(),
      );

  PathUsersByIdGet withCookie(GetUserCookieParameters? value) => PathUsersByIdGet._(
        _id,
        query: _query,
        cookie: value?.toJson(),
      );
}

final class PathUsersByIdGetReady {
  final String _id;
  final Map<String, dynamic> _headers;
  final Map<String, dynamic>? _query;
  final Map<String, dynamic>? _cookie;
  const PathUsersByIdGetReady._(
    this._id, {
    required Map<String, dynamic> headers,
    Map<String, dynamic>? query,
    Map<String, dynamic>? cookie,
  })  : _headers = headers,
        _query = query,
        _cookie = cookie;
  String get method => 'GET';
  String get path => '/users/{id}';

  PathUsersByIdGetReady query({
    bool? expand,
    int? limit,
    List<String?>? tags,
    TransactionSubtype? subtype,
  }) =>
      PathUsersByIdGetReady._(
        _id,
        headers: _headers,
        query: GetUserQueryParameters(
          expand: expand,
          limit: limit,
          tags: tags,
          subtype: subtype,
        ).toJson(),
        cookie: _cookie,
      );

  PathUsersByIdGetReady withQuery(GetUserQueryParameters? value) =>
      PathUsersByIdGetReady._(
        _id,
        headers: _headers,
        query: value?.toJson(),
        cookie: _cookie,
      );

  PathUsersByIdGetReady headers({
    required String xRequestId,
    String? xTrace,
  }) =>
      PathUsersByIdGetReady._(
        _id,
        headers: GetUserHeaderParameters(
          xRequestId: xRequestId,
          xTrace: xTrace,
        ).toJson(),
        query: _query,
        cookie: _cookie,
      );

  PathUsersByIdGetReady withHeaders(GetUserHeaderParameters value) =>
      PathUsersByIdGetReady._(
        _id,
        headers: value.toJson(),
        query: _query,
        cookie: _cookie,
      );

  PathUsersByIdGetReady cookie({
    String? session,
  }) =>
      PathUsersByIdGetReady._(
        _id,
        headers: _headers,
        query: _query,
        cookie: GetUserCookieParameters(session: session).toJson(),
      );

  PathUsersByIdGetReady withCookie(GetUserCookieParameters? value) =>
      PathUsersByIdGetReady._(
        _id,
        headers: _headers,
        query: _query,
        cookie: value?.toJson(),
      );

  OperationRequest<UserModel?, ProblemDetails> get request => (
        method: 'GET',
        path: '/users/{id}',
        pathParams: <String, dynamic>{'id': _id},
        query: _query,
        headers: _headers,
        cookie: _cookie,
        body: null,
        contentType: null,
        decodeResponse: (Object? data) =>
            data == null ? null : UserModel.fromJson(Map<String, dynamic>.from(data as Map)),
        errorDecoders: <int, ProblemDetails Function(Object? data)?>{
          400: (Object? data) => ProblemDetails.fromJson(Map<String, dynamic>.from(data as Map)),
          401: null,
        },
        defaultErrorDecoder: null,
      );
}

final class PathUpload {
  const PathUpload._();
  String get path => '/upload';
  PathUploadPost get post => const PathUploadPost._();
}

final class PathUploadPost {
  final String _contentType;
  const PathUploadPost._({
    String contentType = 'application/json',
  }) : _contentType = contentType;
  String get method => 'POST';
  String get path => '/upload';

  PathUploadPostReady body({
    required String accountId,
    required String binId,
    required List<int> file,
  }) =>
      PathUploadPostReady._(
        body: PostFileUploadRequest(
          accountId: accountId,
          binId: binId,
          file: file,
        ),
        contentType: _contentType,
      );

  PathUploadPostReady withBody(PostFileUploadRequest value) =>
      PathUploadPostReady._(
        body: value,
        contentType: _contentType,
      );

  PathUploadPost contentType(String value) => PathUploadPost._(
        contentType: value,
      );
}

final class PathUploadPostReady {
  final Object? _body;
  final String _contentType;
  const PathUploadPostReady._({
    required Object? body,
    String contentType = 'application/json',
  })  : _body = body,
        _contentType = contentType;
  String get method => 'POST';
  String get path => '/upload';

  PathUploadPostReady body({
    required String accountId,
    required String binId,
    required List<int> file,
  }) =>
      PathUploadPostReady._(
        body: PostFileUploadRequest(
          accountId: accountId,
          binId: binId,
          file: file,
        ),
        contentType: _contentType,
      );

  PathUploadPostReady withBody(PostFileUploadRequest value) =>
      PathUploadPostReady._(
        body: value,
        contentType: _contentType,
      );

  PathUploadPostReady contentType(String value) => PathUploadPostReady._(
        body: _body,
        contentType: value,
      );

  OperationRequest<void, Never> get request => (
        method: 'POST',
        path: '/upload',
        pathParams: null,
        query: null,
        headers: null,
        cookie: null,
        body: _body,
        contentType: _contentType,
        decodeResponse: (Object? _) {},
        errorDecoders: const <int, Never Function(Object? data)?>{},
        defaultErrorDecoder: null,
      );
}

final class PathDefaultError {
  const PathDefaultError._();
  String get path => '/default-error';
  PathDefaultErrorGet get get => const PathDefaultErrorGet._();
}

final class PathDefaultErrorGet {
  const PathDefaultErrorGet._();
  String get method => 'GET';
  String get path => '/default-error';

  OperationRequest<UserModel, ConflictError> get request => (
        method: 'GET',
        path: '/default-error',
        pathParams: null,
        query: null,
        headers: null,
        cookie: null,
        body: null,
        contentType: null,
        decodeResponse: (Object? data) =>
            UserModel.fromJson(Map<String, dynamic>.from(data as Map)),
        errorDecoders: const <int, ConflictError Function(Object? data)?>{},
        defaultErrorDecoder: (Object? data) =>
            ConflictError.fromJson(Map<String, dynamic>.from(data as Map)),
      );
}

sealed class CreateOrderError {
  const CreateOrderError();
  ProblemDetails? get problemDetails => null;
  ConflictError? get conflictError => null;
}

final class CreateOrderErrorProblemDetails extends CreateOrderError {
  final ProblemDetails value;
  const CreateOrderErrorProblemDetails(this.value);

  @override
  ProblemDetails get problemDetails => value;
}

final class CreateOrderErrorConflictError extends CreateOrderError {
  final ConflictError value;
  const CreateOrderErrorConflictError(this.value);

  @override
  ConflictError get conflictError => value;
}

final class PathOrders {
  const PathOrders._();
  String get path => '/orders';
  PathOrdersPost get post => const PathOrdersPost._();
}

final class PathOrdersPost {
  const PathOrdersPost._();
  String get method => 'POST';
  String get path => '/orders';

  OperationRequest<UserModel, CreateOrderError> get request => (
        method: 'POST',
        path: '/orders',
        pathParams: null,
        query: null,
        headers: null,
        cookie: null,
        body: null,
        contentType: null,
        decodeResponse: (Object? data) =>
            UserModel.fromJson(Map<String, dynamic>.from(data as Map)),
        errorDecoders: <int, CreateOrderError Function(Object? data)?>{
          400: (Object? data) => CreateOrderErrorProblemDetails(
                ProblemDetails.fromJson(Map<String, dynamic>.from(data as Map)),
              ),
          409: (Object? data) => CreateOrderErrorConflictError(
                ConflictError.fromJson(Map<String, dynamic>.from(data as Map)),
              ),
        },
        defaultErrorDecoder: null,
      );
}

({HttpTransport transport, List<RawHttpRequest> requests}) createMockTransport(
  FutureOr<RawHttpResponse> Function(RawHttpRequest request) handler,
) {
  final List<RawHttpRequest> requests = <RawHttpRequest>[];
  final HttpTransport transport = HttpTransport.fromHandler((RawHttpRequest request) async {
    requests.add(request);
    return handler(request);
  });
  return (transport: transport, requests: requests);
}

Future<void> main() async {
  var passed = 0;

  // 1. URL joining, path encoding, Tukan query models & enum serialization.
  {
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport(
      (_) => RawHttpResponse.json(<String, dynamic>{'id': '1', 'name': 'Ada'}),
    );

    final TukanClient client = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test///',
        transport: mock.transport,
      ),
    );

    final ApiResult<UserModel, Object?> result = await client.get<UserModel>(
      '/users/{id}',
      pathParams: const GetUserPathParameters(id: 'a/b?c'),
      query: const GetUserQueryParameters(
        expand: false,
        limit: 0,
        tags: <String?>['one', 'two'],
        subtype: TransactionSubtype.transfer,
      ),
      headers: const GetUserHeaderParameters(xRequestId: 'req-42'),
      fromJson: UserModel.fromJson,
    );

    expectTrue(result.isOk, 'result is ok');
    expectEqual(result.data, const UserModel(id: '1', name: 'Ada'), 'decoded user');
    expectEqual(result.response?.statusCode, 200, 'status 200');
    expectEqual(
      mock.requests[0].uri.toString(),
      'https://api.example.test/users/a%2Fb%3Fc?expand=false&limit=0&tags=one&tags=two&subtype=transfer',
      'encoded path and Tukan query parameters',
    );

    // Relative and empty baseUrl.
    final ({HttpTransport transport, List<RawHttpRequest> requests}) relMock = createMockTransport(
      (_) => RawHttpResponse.json('pong'),
    );
    final TukanClient rootClient = TukanClient(
      TukanClientConfig(baseUrl: '', transport: relMock.transport),
    );
    final ApiResult<String, Object?> pingRoot =
        await rootClient.get<String>('/ping', decode: Decoders.string);
    expectEqual(relMock.requests[0].uri.toString(), '/ping', 'empty baseUrl keeps relative path');
    expectEqual(pingRoot.data, 'pong', 'primitive string decoded');

    final ({HttpTransport transport, List<RawHttpRequest> requests}) prefixMock = createMockTransport(
      (_) => RawHttpResponse.json('pong'),
    );
    final TukanClient prefixClient = TukanClient(
      TukanClientConfig(baseUrl: '/proxy/', transport: prefixMock.transport),
    );
    await prefixClient.get<String>('/ping', decode: Decoders.string);
    expectEqual(prefixMock.requests[0].uri.toString(), '/proxy/ping', 'prefix baseUrl trims slash');
    passed++;
  }

  // 2. Null omission in query/headers/cookies and DateTime/object serialization.
  {
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport(
      (_) => RawHttpResponse.empty(statusCode: 204),
    );
    final TukanClient client = TukanClient(
      TukanClientConfig(baseUrl: 'https://api.example.test', transport: mock.transport),
    );

    await client.get<void>(
      '/users/{id}',
      pathParams: <String, Object?>{'id': '42'},
      query: <String, Object?>{
        'expand': null,
        'limit': 5,
        'tags': <Object?>['a', null, 'b'],
      },
      headers: <String, Object?>{
        'X-Request-Id': 'req-null',
        'X-Trace': null,
      },
      cookie: const GetUserCookieParameters(session: null),
    );

    expectEqual(
      mock.requests[0].uri.toString(),
      'https://api.example.test/users/42?limit=5&tags=a&tags=b',
      'null query entries skipped',
    );
    expectEqual(mock.requests[0].headers['x-trace'], null, 'null header omitted');
    expectEqual(mock.requests[0].headers['cookie'], null, 'null cookie omitted');

    await client.get<void>(
      '/cost',
      query: <String, Object?>{
        'filter': <String, int>{'min': 10, 'max': 20},
        'since': DateTime.utc(2026, 1, 2, 3, 4, 5),
        'subtype': TransactionSubtype.card,
      },
    );

    expectEqual(
      mock.requests[1].uri.toString(),
      'https://api.example.test/cost?filter=%7B%22min%22%3A10%2C%22max%22%3A20%7D&since=2026-01-02T03%3A04%3A05.000Z&subtype=card',
      'nested object, DateTime, and enum serialized in query',
    );
    passed++;
  }

  // 3. Missing path parameter returns UnexpectedClientError(requestBuild) without calling transport.
  {
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport(
      (_) => throw StateError('transport should not be called'),
    );
    final TukanClient client = TukanClient(
      TukanClientConfig(baseUrl: 'https://api.example.test', transport: mock.transport),
    );

    final ApiResult<void, Object?> result = await client.get<void>(
      '/users/{id}',
      pathParams: <String, Object?>{},
    );

    expectTrue(result.isError, 'missing path param yields ApiFailure');
    expectTrue(
      result.error is UnexpectedClientError<Object?> &&
          (result.error as UnexpectedClientError<Object?>).stage == ClientErrorStage.requestBuild,
      'missing path param classifies as UnexpectedClientError(requestBuild)',
    );
    expectEqual(result.error?.status, null, 'no status on URL build failure');
    expectEqual(result.response, null, 'no response on URL build failure');
    expectEqual(mock.requests.length, 0, 'transport not called');
    passed++;
  }

  // 4. Case-insensitive base headers merge/override without mutating inputs + cookie formatting.
  {
    final Map<String, String> baseHeaders = <String, String>{
      'Authorization': 'Bearer base-token',
      'X-Trace': 'from-base',
    };
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport(
      (_) => RawHttpResponse.empty(statusCode: 204),
    );
    final TukanClient client = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        headers: baseHeaders,
        transport: mock.transport,
      ),
    );

    await client.get<void>(
      '/users/{id}',
      pathParams: <String, String>{'id': '7'},
      headers: <String, String>{
        'X-Request-Id': 'req-7',
        'x-trace': 'from-request',
        'Accept': 'application/json',
      },
      cookie: const GetUserCookieParameters(session: 'a b;c'),
    );

    final HttpHeadersMap sent = mock.requests[0].headers;
    expectEqual(sent['authorization'], 'Bearer base-token', 'base header preserved');
    expectEqual(sent['x-trace'], 'from-request', 'per-request header overrides case-insensitively');
    expectEqual(sent['x-request-id'], 'req-7', 'request header set');
    expectEqual(sent['accept'], 'application/json', 'extra header set');
    expectEqual(sent['cookie'], 'session=a%20b%3Bc', 'cookie formatted');
    expectEqual(baseHeaders['X-Trace'], 'from-base', 'input map not mutated');
    passed++;
  }

  // 5. JSON body (Tukan model + DELETE) and Decoders.list / enumList / map.
  {
    var step = 0;
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport((_) {
      step++;
      if (step == 1) return RawHttpResponse.empty(statusCode: 200);
      if (step == 2) {
        return RawHttpResponse.json(<Map<String, dynamic>>[
          <String, dynamic>{'id': 'u1', 'name': 'Ada'},
          <String, dynamic>{'id': 'u2', 'name': 'Linus'},
        ]);
      }
      if (step == 3) {
        return RawHttpResponse.json(<String>['card', 'transfer']);
      }
      return RawHttpResponse.json(<String, dynamic>{
        'first': <String, dynamic>{'id': 'u1', 'name': 'Ada'},
      });
    });

    final TukanClient client = TukanClient(
      TukanClientConfig(baseUrl: 'https://api.example.test', transport: mock.transport),
    );

    final ApiResult<void, Object?> deleteRes = await client.delete<void>(
      '/cost',
      body: const UserModel(id: 'acc-1', name: 'Rule'),
    );
    expectTrue(deleteRes.isOk, 'void 200 DELETE succeeds');
    expectEqual(mock.requests[0].method, HttpMethod.delete, 'DELETE method');
    expectEqual(
      utf8.decode(mock.requests[0].body!),
      '{"id":"acc-1","name":"Rule"}',
      'Tukan model encoded via toJson()',
    );
    expectEqual(mock.requests[0].headers['content-type'], 'application/json', 'JSON Content-Type set');

    final ApiResult<List<UserModel>, Object?> listRes = await client.get<List<UserModel>>(
      '/users',
      decode: Decoders.list(UserModel.fromJson),
    );
    expectEqual(listRes.data?.length, 2, 'Decoders.list decodes 2 items');
    expectEqual(listRes.data?[1].name, 'Linus', 'Decoders.list item 2');

    final ApiResult<List<TransactionSubtype>, Object?> enumRes = await client.get<List<TransactionSubtype>>(
      '/subtypes',
      decode: Decoders.enumList(TransactionSubtype.fromJson),
    );
    expectEqual(enumRes.data?[0], TransactionSubtype.card, 'Decoders.enumList item 0');
    expectEqual(enumRes.data?[1], TransactionSubtype.transfer, 'Decoders.enumList item 1');

    final ApiResult<Map<String, UserModel>, Object?> mapRes = await client.get<Map<String, UserModel>>(
      '/users-map',
      decode: Decoders.map(UserModel.fromJson),
    );
    expectEqual(mapRes.data?['first']?.name, 'Ada', 'Decoders.map item');
    passed++;
  }

  // 6. multipart/form-data with Tukan PostFileUploadRequest (List<int>) and MultipartBody.
  {
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport(
      (_) => RawHttpResponse.json(<String, dynamic>{'id': 'upload-1'}, statusCode: 201),
    );
    final TukanClient client = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        headers: const <String, String>{'Content-Type': 'application/json'},
        transport: mock.transport,
      ),
    );

    final ApiResult<Map<String, dynamic>, Object?> tukanUpload =
        await client.post<Map<String, dynamic>>(
      '/file-upload',
      contentType: 'multipart/form-data',
      body: PostFileUploadRequest(
        accountId: 'acc-1',
        binId: 'bin-2',
        file: utf8.encode('col1,col2\n'),
      ),
    );
    expectTrue(tukanUpload.isOk, 'Tukan multipart upload succeeds');
    final String contentType1 = mock.requests[0].headers['content-type'] ?? '';
    expectTrue(
      contentType1.startsWith('multipart/form-data; boundary=----TukanBoundary'),
      'multipart boundary replaces stale base Content-Type',
    );
    final String bodyText1 = utf8.decode(mock.requests[0].body!);
    expectTrue(bodyText1.contains('name="AccountId"\r\n\r\nacc-1\r\n'), 'AccountId part');
    expectTrue(
      bodyText1.contains('name="File"; filename="File"\r\nContent-Type: application/octet-stream\r\n\r\ncol1,col2\n'),
      'Tukan List<int> file encoded as binary part with filename',
    );

    await client.post<void>(
      '/upload',
      body: MultipartBody(<String, Object?>{
        'file': MultipartFile.fromString('hello', filename: 'note.txt'),
        'note': null,
        'tags': <String?>['alpha', null, 'beta'],
      }),
    );
    final String bodyText2 = utf8.decode(mock.requests[1].body!);
    expectTrue(bodyText2.contains('name="file"; filename="note.txt"'), 'MultipartFile filename');
    expectTrue(!bodyText2.contains('name="note"'), 'null multipart field omitted');
    expectTrue(
      bodyText2.contains('name="tags"\r\n\r\nalpha\r\n') &&
          bodyText2.contains('name="tags"\r\n\r\nbeta\r\n'),
      'repeated array fields without nulls',
    );
    passed++;
  }

  // 7. Content-Type precedence: request contentType overrides base; per-request header wins.
  {
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport(
      (_) => RawHttpResponse.json(<String, dynamic>{'ok': true}),
    );
    final TukanClient client = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        headers: const <String, String>{'Content-Type': 'application/json'},
        transport: mock.transport,
      ),
    );

    await client.post<void>(
      '/login',
      contentType: 'application/x-www-form-urlencoded',
      body: <String, String>{'username': 'alice', 'password': 'secret'},
    );
    expectEqual(
      mock.requests[0].headers['content-type'],
      'application/x-www-form-urlencoded',
      'explicit contentType overrides base Content-Type',
    );
    expectEqual(
      utf8.decode(mock.requests[0].body!),
      'username=alice&password=secret',
      'urlencoded payload matches',
    );

    await client.post<void>(
      '/text',
      contentType: 'text/plain',
      body: 'hello world',
    );
    expectEqual(
      mock.requests[1].headers['content-type'],
      'text/plain',
      'text/plain contentType overrides base Content-Type',
    );
    expectEqual(utf8.decode(mock.requests[1].body!), 'hello world', 'text body preserved');

    await client.post<void>(
      '/text',
      contentType: 'text/plain',
      headers: const <String, String>{'Content-Type': 'text/plain; charset=utf-8'},
      body: 'hello charset',
    );
    expectEqual(
      mock.requests[2].headers['content-type'],
      'text/plain; charset=utf-8',
      'per-request Content-Type header takes precedence',
    );
    passed++;
  }

  // 8. HTTP errors: client-level errorFromJson, per-request error override, 401 empty, 502 HTML.
  {
    var step = 0;
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport((_) {
      step++;
      if (step == 1) {
        return RawHttpResponse.json(
          <String, dynamic>{'detail': 'Invalid accountId', 'status': 400},
          statusCode: 400,
          reasonPhrase: 'Bad Request',
          headers: const <String, String>{'Content-Type': 'application/problem+json'},
        );
      }
      if (step == 2) {
        return RawHttpResponse.json(
          <String, dynamic>{'conflictId': 'ord-99'},
          statusCode: 409,
          reasonPhrase: 'Conflict',
        );
      }
      if (step == 3) {
        return RawHttpResponse.empty(statusCode: 401, reasonPhrase: 'Unauthorized');
      }
      return RawHttpResponse.text(
        '<html>Bad Gateway</html>',
        statusCode: 502,
        reasonPhrase: 'Bad Gateway',
        contentType: 'text/html',
      );
    });

    final TukanClient client = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        transport: mock.transport,
        errorFromJson: <int, JsonFactory<Object?>>{
          400: ProblemDetails.fromJson,
        },
      ),
    );

    final ApiResult<void, Object?> r400 = await client.get<void>('/cost');
    expectTrue(r400.isError, '400 returns ApiFailure');
    expectTrue(r400.error is ApiResponseError<Object?>, '400 matches ApiResponseError');
    expectTrue(r400.error!.isStatus(400), '400 status check');
    expectEqual(r400.error!.bodyAs<ProblemDetails>(400)?.detail, 'Invalid accountId', '400 ProblemDetails decoded');
    expectEqual(r400.error!.bodyAs<ConflictError>(409), null, 'bodyAs filters by status');
    expectEqual(r400.error!.message, 'HTTP 400 Bad Request', '400 message');

    final ApiResult<void, Object?> r409 = await client.post<void>(
      '/orders',
      errorFromJson: <int, JsonFactory<Object?>>{409: ConflictError.fromJson},
    );
    expectTrue(r409.error is ApiResponseError<Object?>, '409 matches ApiResponseError');
    expectEqual(r409.error?.bodyAs<ConflictError>(409)?.conflictId, 'ord-99', '409 ConflictError decoded');

    final ApiResult<void, Object?> r401 = await client.get<void>('/cost');
    expectTrue(r401.error is UnexpectedHttpError<Object?>, '401 empty body maps to UnexpectedHttpError');
    expectEqual(r401.error?.status, 401, '401 status');
    expectEqual(r401.error?.body, null, '401 empty body is null');
    expectEqual(r401.error?.rawBody, null, '401 empty rawBody is null');

    final ApiResult<void, Object?> r502 = await client.get<void>('/cost');
    expectTrue(r502.error is UnexpectedHttpError<Object?>, '502 HTML maps to UnexpectedHttpError');
    expectEqual(r502.error?.status, 502, '502 status');
    expectEqual(r502.error?.rawBody, '<html>Bad Gateway</html>', '502 HTML body captured in rawBody');
    expectEqual(r502.error?.bodyAs<String>(), '<html>Bad Gateway</html>', 'bodyAs falls back to rawBody');
    passed++;
  }

  // 9. Malformed JSON on 200 vs 502, decoder FormatException/TypeError -> DecodeError, and HEAD.
  {
    var step = 0;
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport((_) {
      step++;
      if (step == 1) {
        return RawHttpResponse.text(
          '{not-json',
          statusCode: 200,
          contentType: 'application/json',
        );
      }
      if (step == 2) {
        return RawHttpResponse.text(
          '<html>Bad Gateway</html>',
          statusCode: 502,
          reasonPhrase: 'Bad Gateway',
          contentType: 'application/json',
        );
      }
      if (step == 3) {
        return RawHttpResponse.json(<String, dynamic>{'name': 'MissingId'});
      }
      if (step == 4) {
        return RawHttpResponse.json(<String, dynamic>{'id': 123, 'name': 'WrongIdType'});
      }
      return RawHttpResponse(
        statusCode: 200,
        reasonPhrase: 'OK',
        headers: HttpHeadersMap(const <String, String>{
          'Content-Type': 'application/json',
          'Content-Length': '999',
        }),
        bodyBytes: Uint8List(0),
      );
    });
    final TukanClient client = TukanClient(
      TukanClientConfig(baseUrl: 'https://api.example.test', transport: mock.transport),
    );

    final ApiResult<UserModel, Object?> res200 = await client.get<UserModel>('/user', fromJson: UserModel.fromJson);
    expectTrue(res200.isError, 'malformed 200 JSON returns ApiFailure');
    expectTrue(res200.error is DecodeError<Object?>, 'malformed 200 JSON maps to DecodeError');
    expectEqual(res200.error?.status, 200, '200 status preserved');
    expectEqual(res200.error?.body, null, 'malformed 200 JSON leaves body null');
    expectEqual(res200.error?.rawBody, '{not-json', 'malformed 200 JSON preserves rawText in rawBody');
    expectTrue(res200.error?.cause is FormatException, 'malformed 200 JSON keeps FormatException');

    final ApiResult<UserModel, Object?> res502 = await client.get<UserModel>('/user', fromJson: UserModel.fromJson);
    expectTrue(res502.isError, 'malformed 502 JSON returns ApiFailure');
    expectTrue(res502.error is UnexpectedHttpError<Object?>, 'malformed 502 JSON maps to UnexpectedHttpError');
    expectEqual(res502.error?.status, 502, '502 status preserved');
    expectEqual(res502.error?.message, 'HTTP 502 Bad Gateway', '502 message preserved');
    expectEqual(res502.error?.rawBody, '<html>Bad Gateway</html>', '502 raw text preserved in rawBody');
    expectTrue(res502.error?.cause is FormatException, '502 keeps FormatException cause');

    final ApiResult<UserModel, Object?> missingReq = await client.get<UserModel>('/user', fromJson: UserModel.fromJson);
    expectTrue(missingReq.error is DecodeError<Object?>, 'Tukan _requiredJson maps to DecodeError');
    expectTrue(missingReq.error?.cause is FormatException, 'decoder FormatException preserved');

    final ApiResult<UserModel, Object?> wrongType = await client.get<UserModel>('/user', fromJson: UserModel.fromJson);
    expectTrue(wrongType.error is DecodeError<Object?>, 'contract TypeError maps to DecodeError');
    expectTrue(wrongType.error?.cause is TypeError, 'TypeError cause preserved');

    final ApiResult<void, Object?> headRes = await client.head('/user');
    expectTrue(headRes.isOk, 'HEAD succeeds even with JSON Content-Type and Content-Length');
    passed++;
  }

  // 10. NetworkError, CancelledError, and TimeoutError.
  {
    final TukanClient netClient = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        transport: HttpTransport.fromHandler((_) => throw const SocketException('offline')),
      ),
    );
    final ApiResult<void, Object?> netRes = await netClient.get<void>('/versions');
    expectTrue(netRes.isError, 'network error returns ApiFailure');
    expectTrue(netRes.error is NetworkError<Object?> && netRes.error!.isNetworkError, 'NetworkError classified');
    expectTrue(netRes.error!.cause is SocketException, 'SocketException preserved');

    final CancelToken preCancelled = CancelToken()..cancel('user left screen');
    final ApiResult<void, Object?> preCancelRes = await netClient.get<void>(
      '/versions',
      cancelToken: preCancelled,
    );
    expectTrue(preCancelRes.isError, 'pre-cancelled request fails');
    expectTrue(
      preCancelRes.error is CancelledError<Object?> &&
          preCancelRes.error!.isCancelled &&
          (preCancelRes.error as CancelledError<Object?>).reason == 'user left screen',
      'CancelledError preserves reason',
    );

    final TukanClient slowClient = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        timeout: const Duration(milliseconds: 25),
        transport: HttpTransport.fromHandler((_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return RawHttpResponse.empty();
        }),
      ),
    );
    final ApiResult<void, Object?> timedOut = await slowClient.get<void>('/versions');
    expectTrue(timedOut.isError, 'timeout returns ApiFailure');
    expectTrue(
      timedOut.error is TimeoutError<Object?> &&
          timedOut.error!.isTimeout &&
          (timedOut.error as TimeoutError<Object?>).timeout == const Duration(milliseconds: 25),
      'TimeoutError preserves timeout duration',
    );
    passed++;
  }

  // 11. Dynamic async headersProvider, onRequest, onResponse (401 retry), and onError hooks.
  {
    final List<String> events = <String>[];
    var attempt = 0;

    late final HttpTransport mockTransport;
    mockTransport = HttpTransport.fromHandler((RawHttpRequest req) {
      attempt++;
      events.add('fetch:$attempt:${req.uri}');
      if (attempt == 1) {
        return RawHttpResponse.empty(statusCode: 401, reasonPhrase: 'Unauthorized');
      }
      return RawHttpResponse.json(<String, dynamic>{'id': '1', 'name': 'Refreshed'});
    });

    final TukanClient client = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        transport: mockTransport,
        headersProvider: (HeadersContext ctx) async => <String, String>{
          'Authorization': 'Bearer initial-${ctx.method.name}',
          'X-Source': 'dynamic',
        },
        onRequest: <OnRequestHook>[
          (RequestContext ctx) {
            events.add('onRequest:${ctx.method.name}');
            ctx.headers['X-Hook-Added'] = 'yes';
            ctx.uri = ctx.uri.replace(queryParameters: <String, String>{'fromHook': '1'});
          },
        ],
        onResponse: <OnResponseHook>[
          (RequestContext ctx, RawHttpResponse res) async {
            events.add('onResponse:${res.statusCode}');
            if (res.statusCode == 401) {
              ctx.headers['Authorization'] = 'Bearer refreshed';
              return mockTransport.send(
                RawHttpRequest(
                  method: ctx.method,
                  uri: ctx.uri,
                  headers: ctx.headers,
                  body: ctx.body,
                ),
              );
            }
            return null;
          },
        ],
        onError: <OnErrorHook>[
          (RequestContext ctx, ApiError<Object?> err) {
            events.add('onError:${err.status}');
          },
        ],
      ),
    );

    final ApiResult<UserModel, Object?> res = await client.get<UserModel>(
      '/users/{id}',
      pathParams: const GetUserPathParameters(id: '1'),
      headers: const <String, String>{'X-Source': 'per-request'},
      fromJson: UserModel.fromJson,
    );

    expectTrue(res.isOk, '401 retry in onResponse succeeds');
    expectEqual(res.data?.name, 'Refreshed', 'retried payload decoded');
    expectDeepEqual(
      events,
      <String>[
        'onRequest:get',
        'fetch:1:https://api.example.test/users/1?fromHook=1',
        'onResponse:401',
        'fetch:2:https://api.example.test/users/1?fromHook=1',
      ],
      'hook execution order',
    );

    // Throwing hooks never escape and classify as UnexpectedClientError(hook).
    final TukanClient faultyClient = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        transport: mockTransport,
        onRequest: <OnRequestHook>[(_) => throw StateError('request hook boom')],
        onError: <OnErrorHook>[(_, __) => throw StateError('error hook boom')],
      ),
    );
    final ApiResult<void, Object?> hookErr = await faultyClient.get<void>('/versions');
    expectTrue(hookErr.isError, 'throwing hook returns ApiFailure');
    expectTrue(
      hookErr.error is UnexpectedClientError<Object?> &&
          (hookErr.error as UnexpectedClientError<Object?>).stage == ClientErrorStage.hook,
      'throwing hook classified with stage=hook',
    );
    expectTrue(hookErr.error!.message.contains('error hook boom'), 'throwing onError captured');
    passed++;
  }

  // 12. ApiEndpoint<T> and PathClient ergonomics.
  {
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport(
      (_) => RawHttpResponse.json(<String, dynamic>{'id': '9', 'name': 'Grace'}),
    );
    final TukanClient client = TukanClient(
      TukanClientConfig(baseUrl: 'https://api.example.test', transport: mock.transport),
    );

    const ApiEndpoint<UserModel> getUser = ApiEndpoint<UserModel>(
      method: HttpMethod.get,
      path: '/users/{id}',
      fromJson: UserModel.fromJson,
      errorFromJson: <int, JsonFactory<Object?>>{400: ProblemDetails.fromJson},
    );

    final ApiResult<UserModel, Object?> viaEndpoint = await client.call(
      getUser,
      pathParams: const GetUserPathParameters(id: '9'),
    );
    expectEqual(viaEndpoint.data?.name, 'Grace', 'ApiEndpoint call');

    final ApiResult<UserModel, Object?> viaPath = await client.path('/users/{id}').get<UserModel>(
      pathParams: const GetUserPathParameters(id: '9'),
      fromJson: UserModel.fromJson,
    );
    expectEqual(viaPath.data?.name, 'Grace', 'PathClient call');
    passed++;
  }

  // 13. Binary (Uint8List) and text/csv response payloads.
  {
    var step = 0;
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport((_) {
      step++;
      if (step == 1) {
        return RawHttpResponse(
          statusCode: 200,
          headers: HttpHeadersMap(const <String, String>{'Content-Type': 'application/octet-stream'}),
          bodyBytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        );
      }
      return RawHttpResponse.text('a,b\n1,2\n', contentType: 'text/csv');
    });
    final TukanClient client = TukanClient(
      TukanClientConfig(baseUrl: 'https://api.example.test', transport: mock.transport),
    );

    final ApiResult<Uint8List, Object?> binRes = await client.get<Uint8List>('/export.bin', decode: Decoders.bytes);
    expectDeepEqual(binRes.data, <int>[1, 2, 3, 4], 'binary Uint8List decoded');

    final ApiResult<String, Object?> csvRes = await client.get<String>('/export.csv', decode: Decoders.string);
    expectEqual(csvRes.data, 'a,b\n1,2\n', 'text/csv decoded as String');
    passed++;
  }

  // 14. Real dart:io HttpServer loopback integration with default IoHttpTransport.
  {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final TukanClient client = TukanClient(
      TukanClientConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        errorFromJson: <int, JsonFactory<Object?>>{400: ProblemDetails.fromJson},
      ),
    );

    final StreamSubscription<HttpRequest> sub = server.listen((HttpRequest req) async {
      if (req.uri.path == '/users/42' && req.method == 'GET') {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..headers.set('X-Echo-Auth', req.headers.value('authorization') ?? '')
          ..write(jsonEncode(<String, dynamic>{
            'id': '42',
            'name': req.uri.queryParameters['tag'] ?? 'unknown',
          }));
        await req.response.close();
        return;
      }

      if (req.uri.path == '/upload' && req.method == 'POST') {
        final List<int> bodyBytes = await req.fold<List<int>>(
          <int>[],
          (List<int> acc, List<int> chunk) => acc..addAll(chunk),
        );
        req.response
          ..statusCode = HttpStatus.created
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, dynamic>{
            'bytes': bodyBytes.length,
            'hasBoundary': (req.headers.contentType?.mimeType == 'multipart/form-data'),
          }));
        await req.response.close();
        return;
      }

      if (req.uri.path == '/bad') {
        req.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType('application', 'problem+json')
          ..write(jsonEncode(<String, dynamic>{'title': 'Bad Input', 'detail': 'Nope', 'status': 400}));
        await req.response.close();
        return;
      }

      if (req.uri.path == '/head' && req.method == 'HEAD') {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..headers.contentLength = 123;
        await req.response.close();
        return;
      }

      if (req.uri.path == '/slow') {
        await Future<void>.delayed(const Duration(seconds: 2));
        req.response.statusCode = HttpStatus.ok;
        await req.response.close();
        return;
      }

      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    });

    try {
      final ApiResult<UserModel, Object?> getRes = await client.get<UserModel>(
        '/users/{id}',
        pathParams: const <String, String>{'id': '42'},
        query: const <String, String>{'tag': 'loopback'},
        headers: const <String, String>{'Authorization': 'Bearer real-io'},
        fromJson: UserModel.fromJson,
      );
      expectTrue(getRes.isOk, 'loopback GET succeeds');
      expectEqual(getRes.data, const UserModel(id: '42', name: 'loopback'), 'loopback JSON decoded');
      expectEqual(getRes.response?.headers['x-echo-auth'], 'Bearer real-io', 'real header echoed');

      final ApiResult<Map<String, dynamic>, Object?> uploadRes =
          await client.post<Map<String, dynamic>>(
        '/upload',
        contentType: 'multipart/form-data',
        body: PostFileUploadRequest(
          accountId: 'a1',
          binId: 'b1',
          file: utf8.encode('csv-bytes'),
        ),
      );
      expectTrue(uploadRes.isOk, 'loopback multipart upload succeeds');
      expectEqual(uploadRes.data?['hasBoundary'], true, 'server saw multipart/form-data');

      final ApiResult<void, Object?> badRes = await client.get<void>('/bad');
      expectTrue(badRes.isError && badRes.error!.isStatus(400), 'loopback 400 ProblemDetails');
      expectEqual(badRes.error!.bodyAs<ProblemDetails>(400)?.detail, 'Nope', 'loopback ProblemDetails detail');

      final ApiResult<void, Object?> headRes = await client.head('/head');
      expectTrue(headRes.isOk, 'loopback HEAD succeeds');

      final ApiResult<void, Object?> slowRes = await client.get<void>(
        '/slow',
        timeout: const Duration(milliseconds: 40),
      );
      expectTrue(slowRes.isError && slowRes.error!.isTimeout, 'loopback timeout aborts real socket');
    } finally {
      client.close();
      await sub.cancel();
      await server.close(force: true);
    }
    passed++;
  }

  // 15. Type-safe client.send(Paths....) with OperationRequest<T, E> and typed error narrowing.
  {
    var step = 0;
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport((_) {
      step++;
      if (step == 1) {
        return RawHttpResponse.json(<String, dynamic>{'id': 'u-9', 'name': 'Ada'});
      }
      if (step == 2) {
        return RawHttpResponse.empty(statusCode: 204);
      }
      if (step == 3) {
        return RawHttpResponse.json(
          <String, dynamic>{'title': 'Bad', 'detail': 'Missing field', 'status': 400},
          statusCode: 400,
          headers: const <String, String>{'Content-Type': 'application/problem+json'},
        );
      }
      if (step == 4 || step == 5) {
        return RawHttpResponse.empty(statusCode: 204);
      }
      if (step == 6) {
        return RawHttpResponse.json(
          <String, dynamic>{'conflictId': 'fallback-err'},
          statusCode: 503,
        );
      }
      if (step == 7) {
        return RawHttpResponse.json(
          <String, dynamic>{'title': 'Invalid', 'detail': 'Order invalid', 'status': 400},
          statusCode: 400,
        );
      }
      if (step == 8) {
        return RawHttpResponse.json(
          <String, dynamic>{'conflictId': 'dup-1'},
          statusCode: 409,
        );
      }
      return RawHttpResponse.text('Bad Gateway', statusCode: 502, reasonPhrase: 'Bad Gateway');
    });

    final TukanClient client = TukanClient(
      TukanClientConfig(baseUrl: 'https://api.example.test', transport: mock.transport),
    );

    final PathUsersByIdGet getUserOp = Paths.users.byId('u-9').get;
    expectEqual(Paths.users.byId.path, '/users/{id}', 'path node exposes exact OpenAPI template');
    expectEqual(getUserOp.method, 'GET', 'operation exposes method');
    expectEqual(getUserOp.path, '/users/{id}', 'operation exposes exact path');

    // Also test implicit type inference for both T and E (no explicit type annotation on resOk).
    final resOk = await client.send(
      getUserOp
          .query(limit: 10)
          .headers(xRequestId: 'req-9', xTrace: 'op-trace')
          .cookie(session: 's1')
          .request,
      headers: const <String, String>{
        'Authorization': 'Bearer extra',
        'x-trace': 'caller-override',
      },
      cookie: const <String, String>{'locale': 'en'},
    );
    final UserModel? inferredUser = resOk.data;
    expectTrue(resOk.isOk, 'send(Paths.users.byId.get) succeeds');
    expectEqual(inferredUser, const UserModel(id: 'u-9', name: 'Ada'), 'UserModel decoded and inferred automatically');
    expectEqual(
      mock.requests[0].uri.toString(),
      'https://api.example.test/users/u-9?limit=10',
      'Paths operation built URL',
    );
    expectEqual(mock.requests[0].headers['x-request-id'], 'req-9', 'op header sent');
    expectEqual(mock.requests[0].headers['x-trace'], 'caller-override', 'extra header overrides op header');
    expectEqual(mock.requests[0].headers['authorization'], 'Bearer extra', 'extra Authorization header merged');
    expectEqual(mock.requests[0].headers['cookie'], 'session=s1; locale=en', 'cookies merged');

    final res204 = await client.send(
      getUserOp.withHeaders(const GetUserHeaderParameters(xRequestId: 'req-204')).request,
    );
    expectTrue(res204.isOk, 'send handles 204 for nullable 200+204 operation');
    expectEqual(res204.data, null, '204 decodes to null');

    // Direct typed error access via `error.body` without bodyAs<ProblemDetails>()!
    final res400 = await client.send(
      getUserOp.headers(xRequestId: 'req-400').request,
    );
    expectTrue(res400.error is ApiResponseError<ProblemDetails>, '400 narrows to ApiResponseError<ProblemDetails>');
    expectEqual(
      res400.error?.body?.detail,
      'Missing field',
      'error.body has inferred type ProblemDetails? without bodyAs',
    );
    if (res400 case ApiFailure<UserModel?, ProblemDetails>(
        error: ApiResponseError<ProblemDetails>(:final body))) {
      expectEqual(body.title, 'Bad', 'non-null ProblemDetails matched via ApiResponseError');
    } else {
      throw AssertionError('Expected ApiResponseError<ProblemDetails>');
    }

    final PathUploadPost uploadOp = Paths.upload.post;
    final ApiResult<void, Never> uploadRes = await client.send(
      uploadOp
          .contentType('multipart/form-data')
          .body(accountId: 'a1', binId: 'b1', file: utf8.encode('csv'))
          .request,
    );
    expectTrue(uploadRes.isOk, 'void multipart send succeeds');
    expectTrue(
      (mock.requests[3].headers['content-type'] ?? '').startsWith('multipart/form-data; boundary='),
      'multipart contentType forwarded from OperationRequest',
    );

    final ApiResult<void, Never> uploadReversedOrder = await client.send(
      uploadOp
          .body(accountId: 'a1', binId: 'b1', file: utf8.encode('csv'))
          .contentType('multipart/form-data')
          .request,
    );
    expectTrue(uploadReversedOrder.isOk, 'reversed contentType order also succeeds');

    final defErrRes = await client.send(Paths.defaultError.get.request);
    final UserModel? inferredDefErrData = defErrRes.data;
    expectEqual(inferredDefErrData, null, 'error result has null data');
    expectTrue(defErrRes.error is ApiResponseError<ConflictError>, 'defaultErrorDecoder matches ApiResponseError');
    expectEqual(
      defErrRes.error?.body?.conflictId,
      'fallback-err',
      'defaultErrorDecoder decoded typed ConflictError directly into body',
    );

    // Multi-error sealed union narrows cleanly via getters or exhaustive switch without casts.
    final order400 = await client.send(Paths.orders.post.request);
    expectEqual(order400.error?.body?.problemDetails?.detail, 'Order invalid', '400 sealed getter access');

    final order409 = await client.send(Paths.orders.post.request);
    switch (order409) {
      case ApiSuccess<UserModel, CreateOrderError>():
        throw AssertionError('Expected 409 error');
      case ApiFailure<UserModel, CreateOrderError>(error: ApiResponseError<CreateOrderError>(:final body)):
        switch (body) {
          case CreateOrderErrorProblemDetails():
            throw AssertionError('Expected CreateOrderErrorConflictError');
          case CreateOrderErrorConflictError(:final value):
            expectEqual(value.conflictId, 'dup-1', 'exhaustive switch on sealed error union');
        }
      case ApiFailure<UserModel, CreateOrderError>():
        throw AssertionError('Expected ApiResponseError');
    }

    final order502 = await client.send(Paths.orders.post.request);
    expectTrue(
      order502.error is UnexpectedHttpError<CreateOrderError>,
      'undeclared 502 on typed op maps to UnexpectedHttpError',
    );
    expectEqual(order502.error?.body, null, 'UnexpectedHttpError keeps typed body null');
    expectEqual(order502.error?.rawBody, 'Bad Gateway', 'UnexpectedHttpError preserves rawBody');
    passed++;
  }

  // 16. R4: Array header joining and Cookie appending without overwriting.
  {
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport(
      (_) => RawHttpResponse.empty(statusCode: 204),
    );
    final TukanClient client = TukanClient(
      TukanClientConfig(baseUrl: 'https://api.example.test', transport: mock.transport),
    );

    await client.get<void>(
      '/headers-check',
      headers: <String, Object?>{
        'X-Multi': <Object?>['one', null, 2],
        'Cookie': 'theme=dark',
      },
      cookie: <String, Object?>{'session': 'tok 1'},
    );

    final HttpHeadersMap sent = mock.requests[0].headers;
    expectEqual(sent['x-multi'], 'one, 2', 'array header joins non-null values');
    expectEqual(sent['cookie'], 'theme=dark; session=tok%201', 'cookie appends onto existing Cookie header');
    passed++;
  }

  // 17. R5: MultipartFile (filename escaping, MIME, multi-file, DateTime, enum, JSON), binary upload, raw urlencoded, and requestBuild errors.
  {
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport((RawHttpRequest req) {
      if (req.uri.path == '/binary-upload') {
        return RawHttpResponse.json(<String, dynamic>{'size': req.body?.length ?? 0});
      }
      return RawHttpResponse.json(<String, dynamic>{'ok': true}, statusCode: 201);
    });
    final TukanClient client = TukanClient(
      TukanClientConfig(baseUrl: 'https://api.example.test', transport: mock.transport),
    );

    await client.post<Map<String, dynamic>>(
      '/files-multi',
      body: MultipartBody(<String, Object?>{
        'primary': MultipartFile(
          Uint8List.fromList(utf8.encode('pdf-data')),
          filename: 're"p\\ort\r\n.pdf',
          contentType: 'application/pdf',
        ),
        'attachments': <MultipartFile>[
          MultipartFile.fromBytes(utf8.encode('img-a'), filename: 'a.png', contentType: 'image/png'),
          MultipartFile.fromString('raw-b', filename: 'b.txt'),
        ],
        'createdAt': DateTime.utc(2026, 2, 3, 4, 5, 6),
        'subtype': TransactionSubtype.transfer,
        'meta': <String, Object?>{'source': 'mobile', 'retry': false},
      }),
    );

    final String bodyText = utf8.decode(mock.requests[0].body!);
    expectTrue(
      bodyText.contains('name="primary"; filename="re\\"p\\\\ort.pdf"\r\nContent-Type: application/pdf\r\n\r\npdf-data'),
      'MultipartFile escapes filename quotes/slashes/newlines and preserves MIME',
    );
    expectTrue(
      bodyText.contains('name="attachments"; filename="a.png"\r\nContent-Type: image/png') &&
          bodyText.contains('name="attachments"; filename="b.txt"\r\nContent-Type: text/plain; charset=utf-8'),
      'List<MultipartFile> emits repeated multipart file parts',
    );
    expectTrue(
      bodyText.contains('name="createdAt"\r\n\r\n2026-02-03T04:05:06.000Z\r\n'),
      'DateTime multipart field uses ISO-8601',
    );
    expectTrue(
      bodyText.contains('name="subtype"\r\n\r\ntransfer\r\n'),
      'enum multipart field unwraps via toJson()',
    );
    expectTrue(
      bodyText.contains('name="meta"\r\nContent-Type: application/json\r\n\r\n{"source":"mobile","retry":false}\r\n'),
      'nested map multipart field uses application/json',
    );

    final ApiResult<Map<String, dynamic>, Object?> binUp = await client.post<Map<String, dynamic>>(
      '/binary-upload',
      contentType: 'application/octet-stream',
      body: Uint8List.fromList(<int>[5, 6, 7, 8, 9]),
    );
    expectEqual(binUp.data?['size'], 5, 'raw Uint8List upload succeeds');
    expectEqual(mock.requests[1].headers['content-type'], 'application/octet-stream', 'octet-stream header preserved');

    await client.post<void>(
      '/form-raw',
      contentType: 'application/x-www-form-urlencoded',
      body: 'raw=value&mode=1',
    );
    expectEqual(utf8.decode(mock.requests[2].body!), 'raw=value&mode=1', 'raw urlencoded string preserved');

    final int countBeforeInvalid = mock.requests.length;
    final ApiResult<void, Object?> badText = await client.post<void>(
      '/bad-text',
      contentType: 'text/plain',
      body: 42,
    );
    expectTrue(
      badText.error is UnexpectedClientError<Object?> &&
          (badText.error as UnexpectedClientError<Object?>).stage == ClientErrorStage.requestBuild,
      'unsupported body type for text/plain fails at requestBuild',
    );

    final ApiResult<void, Object?> badMultipart = await client.post<void>(
      '/bad-multi',
      contentType: 'multipart/form-data',
      body: 'not-a-map',
    );
    expectTrue(
      badMultipart.error is UnexpectedClientError<Object?> &&
          (badMultipart.error as UnexpectedClientError<Object?>).stage == ClientErrorStage.requestBuild,
      'non-map multipart body fails at requestBuild',
    );

    final ApiResult<void, Object?> unencodableJson = await client.post<void>(
      '/bad-json',
      body: Object(),
    );
    expectTrue(
      unencodableJson.error is UnexpectedClientError<Object?> &&
          (unencodableJson.error as UnexpectedClientError<Object?>).stage == ClientErrorStage.requestBuild,
      'JsonUnsupportedObjectError maps to requestBuild',
    );
    expectEqual(mock.requests.length, countBeforeInvalid, 'transport never called on requestBuild errors');
    passed++;
  }

  // 18. R6 & R7: Whitespace JSON, 205/304, E=Never with global errorFromJson, and throwing error decoder.
  {
    var step = 0;
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport((_) {
      step++;
      if (step == 1) {
        return RawHttpResponse.text('  \n\t ', contentType: 'application/json');
      }
      if (step == 2) {
        return RawHttpResponse.empty(statusCode: 205, reasonPhrase: 'Reset Content');
      }
      if (step == 3) {
        return RawHttpResponse.empty(statusCode: 304, reasonPhrase: 'Not Modified');
      }
      if (step == 4) {
        return RawHttpResponse.json(
          <String, dynamic>{'title': 'Global', 'detail': 'Mismatch with Never', 'status': 400},
          statusCode: 400,
        );
      }
      return RawHttpResponse.json(
        <String, dynamic>{'detail': 'Missing required conflictId'},
        statusCode: 409,
      );
    });

    final TukanClient client = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        transport: mock.transport,
        errorFromJson: <int, JsonFactory<Object?>>{
          400: ProblemDetails.fromJson,
          409: ConflictError.fromJson,
        },
      ),
    );

    final ApiResult<UserModel?, Object?> wsRes = await client.get<UserModel?>('/ws');
    expectTrue(wsRes.isOk, 'whitespace JSON succeeds');
    expectEqual(wsRes.data, null, 'whitespace JSON returns null');

    final ApiResult<void, Object?> r205 = await client.get<void>('/r205');
    expectTrue(r205.isOk, '205 Reset Content succeeds');

    final ApiResult<void, Object?> r304 = await client.get<void>('/r304');
    expectTrue(r304.error is UnexpectedHttpError<Object?>, '304 skips JSON error decoding');
    expectEqual(r304.error?.status, 304, '304 status preserved');
    expectEqual(r304.error?.rawBody, null, '304 skips body parsing');

    // Operation with E = Never must classify global ProblemDetails into UnexpectedHttpError<Never> with rawBody.
    final ApiResult<void, Never> neverErrRes = await client.send(
      Paths.upload.post
          .body(accountId: 'a', binId: 'b', file: <int>[1])
          .request,
    );
    expectTrue(neverErrRes.error is UnexpectedHttpError<Never>, 'E=Never routes global decoder to UnexpectedHttpError');
    expectTrue(neverErrRes.error?.rawBody is ProblemDetails, 'rawBody preserves mismatched decoded ProblemDetails');

    // Throwing error decoder -> UnexpectedHttpError with cause and rawBody preserved.
    final ApiResult<void, Object?> badErrDecode = await client.post<void>('/orders');
    expectTrue(badErrDecode.error is UnexpectedHttpError<Object?>, 'throwing error decoder becomes UnexpectedHttpError');
    expectTrue(badErrDecode.error?.cause is FormatException, 'error decoder FormatException preserved');
    expectTrue(badErrDecode.error?.stackTrace != null, 'error decoder stackTrace preserved');
    expectTrue(badErrDecode.error?.rawBody is Map, 'rawBody preserved when error decoder throws');
    passed++;
  }

  // 19. R8: Chained onRequest/onResponse hooks, header remove, body mutation, throwing hook & internal transport Error.
  {
    final List<String> trace = <String>[];
    final ({HttpTransport transport, List<RawHttpRequest> requests}) mock = createMockTransport(
      (_) => RawHttpResponse.json(<String, dynamic>{'id': 'u-1', 'name': 'FromServer'}),
    );

    final TukanClient client = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        transport: mock.transport,
        headers: const <String, String>{
          'X-Drop-Me': 'drop',
          'X-Override': 'base',
        },
        onRequest: <OnRequestHook>[
          (RequestContext ctx) async {
            trace.add('req-1');
            ctx.headers.remove('X-Drop-Me');
            ctx.headers.set('X-Override', 'from-hook-1');
            ctx.headers.set('X-Hook-1', 'a');
            ctx.uri = ctx.uri.replace(queryParameters: <String, String>{'step': '1'});
            ctx.body = Uint8List.fromList(utf8.encode('{"name":"ModifiedByHook"}'));
            ctx.extra['step'] = 1;
          },
          (RequestContext ctx) {
            trace.add('req-2:${ctx.headers.get('x-override')}:${ctx.extra['step']}');
            ctx.headers.set('X-Hook-2', 'b');
          },
        ],
        onResponse: <OnResponseHook>[
          (RequestContext ctx, RawHttpResponse res) {
            trace.add('res-1');
            return RawHttpResponse.json(<String, dynamic>{'id': 'u-1', 'name': 'Replaced-1'});
          },
          (RequestContext ctx, RawHttpResponse res) async {
            trace.add('res-2');
            final Map<String, dynamic> decoded = jsonDecode(res.bodyText) as Map<String, dynamic>;
            return RawHttpResponse.json(<String, dynamic>{
              'id': decoded['id'],
              'name': '${decoded['name']}+2',
            });
          },
        ],
      ),
    );

    final Map<String, Object?> callerExtra = <String, Object?>{'caller': true};
    final ApiResult<UserModel, Object?> hookChainRes = await client.put<UserModel>(
      '/users/{id}',
      pathParams: const <String, String>{'id': 'u-1'},
      body: const <String, String>{'name': 'Original'},
      fromJson: UserModel.fromJson,
      extra: callerExtra,
    );

    expectTrue(hookChainRes.isOk, 'chained hooks succeed');
    expectEqual(hookChainRes.data?.name, 'Replaced-1+2', 'chained onResponse replacements observed');
    expectEqual(callerExtra.containsKey('step'), false, 'caller extra map not mutated');
    expectEqual(mock.requests[0].headers['x-drop-me'], null, 'onRequest removed header');
    expectEqual(mock.requests[0].headers['x-override'], 'from-hook-1', 'onRequest overrode header');
    expectEqual(mock.requests[0].headers['x-hook-1'], 'a', 'hook 1 header sent');
    expectEqual(mock.requests[0].headers['x-hook-2'], 'b', 'hook 2 header sent');
    expectEqual(utf8.decode(mock.requests[0].body!), '{"name":"ModifiedByHook"}', 'onRequest body mutation sent');
    expectDeepEqual(trace, <String>['req-1', 'req-2:from-hook-1:1', 'res-1', 'res-2'], 'hook chain order');

    // Throwing headersProvider and throwing onResponse hook -> UnexpectedClientError(hook).
    final TukanClient badHeadersClient = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        transport: mock.transport,
        headersProvider: (_) => throw StateError('headers boom'),
      ),
    );
    final ApiResult<void, Object?> hdrErr = await badHeadersClient.get<void>('/versions');
    expectTrue(
      hdrErr.error is UnexpectedClientError<Object?> &&
          (hdrErr.error as UnexpectedClientError<Object?>).stage == ClientErrorStage.hook,
      'throwing headersProvider has stage=hook',
    );

    final TukanClient badOnResClient = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        transport: mock.transport,
        onResponse: <OnResponseHook>[(_, __) => throw StateError('onResponse boom')],
      ),
    );
    final ApiResult<void, Object?> onResErr = await badOnResClient.get<void>('/versions');
    expectTrue(
      onResErr.error is UnexpectedClientError<Object?> &&
          (onResErr.error as UnexpectedClientError<Object?>).stage == ClientErrorStage.hook,
      'throwing onResponse has stage=hook',
    );
    expectEqual(onResErr.error?.status, 200, 'throwing onResponse preserves response status');

    // Transport throwing a Dart Error (not Exception) -> UnexpectedClientError(internal).
    final TukanClient crashTransportClient = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        transport: HttpTransport.fromHandler((_) => throw StateError('transport bug')),
      ),
    );
    final ApiResult<void, Object?> internalErr = await crashTransportClient.get<void>('/versions');
    expectTrue(
      internalErr.error is UnexpectedClientError<Object?> &&
          (internalErr.error as UnexpectedClientError<Object?>).stage == ClientErrorStage.internal,
      'transport StateError maps to UnexpectedClientError(internal)',
    );
    passed++;
  }

  // 20. R9: Bounded 503 retries, concurrent single-flight 401 refresh, and transport-level NetworkError retries.
  {
    // 20a. Bounded 503 retry recovering on attempt 3 and stopping at maxRetries.
    var retryCalls = 0;
    var alwaysFail = false;
    late final HttpTransport retryTransport;
    retryTransport = HttpTransport.fromHandler((_) {
      retryCalls++;
      if (alwaysFail || retryCalls < 3) {
        return RawHttpResponse.text('Busy', statusCode: 503, reasonPhrase: 'Service Unavailable');
      }
      return RawHttpResponse.json(<String, dynamic>{'id': '1', 'name': 'Recovered'});
    });

    final TukanClient retryClient = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        transport: retryTransport,
        onResponse: <OnResponseHook>[
          (RequestContext ctx, RawHttpResponse res) async {
            var current = res;
            var retries = (ctx.extra['retries'] as int?) ?? 0;
            while (current.statusCode == 503 && retries < 2) {
              retries++;
              ctx.extra['retries'] = retries;
              current = await retryTransport.send(
                RawHttpRequest(
                  method: ctx.method,
                  uri: ctx.uri,
                  headers: ctx.headers,
                  body: ctx.body,
                ),
              );
            }
            return identical(current, res) ? null : current;
          },
        ],
      ),
    );

    final ApiResult<UserModel, Object?> recRes =
        await retryClient.get<UserModel>('/retry', fromJson: UserModel.fromJson);
    expectTrue(recRes.isOk, 'bounded 503 retry recovers on attempt 3');
    expectEqual(recRes.data?.name, 'Recovered', 'recovered payload decoded');
    expectEqual(retryCalls, 3, 'transport called 3 times to recover');

    alwaysFail = true;
    final int beforeExhaust = retryCalls;
    final ApiResult<UserModel, Object?> exhRes =
        await retryClient.get<UserModel>('/retry', fromJson: UserModel.fromJson);
    expectTrue(exhRes.error is UnexpectedHttpError<Object?>, 'exhausted 503 stops cleanly');
    expectEqual(exhRes.error?.status, 503, 'exhausted 503 status preserved');
    expectEqual(retryCalls - beforeExhaust, 3, 'bounded to 1 initial + 2 retries');

    // 20b. Concurrent single-flight 401 refresh + retry-once guard.
    var activeToken = 'expired-token';
    var refreshCount = 0;
    Future<void>? inflightRefresh;
    var forcePersistent401 = false;

    late final HttpTransport authTransport;
    authTransport = HttpTransport.fromHandler((RawHttpRequest req) {
      if (forcePersistent401 || req.headers.get('authorization') != 'Bearer fresh-token') {
        return RawHttpResponse.empty(statusCode: 401, reasonPhrase: 'Unauthorized');
      }
      return RawHttpResponse.json(<String, dynamic>{'id': 'u-9', 'name': 'Authed'});
    });

    Future<void> runSingleFlightRefresh() {
      final Future<void>? existing = inflightRefresh;
      if (existing != null) return existing;
      final Future<void> pending = () async {
        refreshCount++;
        await Future<void>.delayed(const Duration(milliseconds: 15));
        activeToken = 'fresh-token';
      }()
          .whenComplete(() {
        inflightRefresh = null;
      });
      inflightRefresh = pending;
      return pending;
    }

    final TukanClient singleFlightClient = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        transport: authTransport,
        headersProvider: (_) => <String, String>{'Authorization': 'Bearer $activeToken'},
        onResponse: <OnResponseHook>[
          (RequestContext ctx, RawHttpResponse res) async {
            if (res.statusCode != 401 || ctx.extra['_retried'] == true) {
              return null;
            }
            await runSingleFlightRefresh();
            ctx.extra['_retried'] = true;
            ctx.headers.set('Authorization', 'Bearer $activeToken');
            return authTransport.send(
              RawHttpRequest(
                method: ctx.method,
                uri: ctx.uri,
                headers: ctx.headers,
                body: ctx.body,
              ),
            );
          },
        ],
      ),
    );

    final List<ApiResult<UserModel?, ProblemDetails>> parallel = await Future.wait(<Future<ApiResult<UserModel?, ProblemDetails>>>[
      singleFlightClient.send(Paths.users.byId('u-9').get.headers(xRequestId: 'r1').request),
      singleFlightClient.send(Paths.users.byId('u-9').get.headers(xRequestId: 'r2').request),
    ]);
    expectTrue(parallel[0].isOk && parallel[1].isOk, 'both concurrent requests succeed after single-flight refresh');
    expectEqual(refreshCount, 1, 'concurrent 401 responses share one refresh call');

    forcePersistent401 = true;
    final ApiResult<UserModel?, ProblemDetails> stop401 = await singleFlightClient.send(
      Paths.users.byId('u-9').get.headers(xRequestId: 'r3').request,
    );
    expectEqual(stop401.error?.status, 401, 'persistent 401 stops after retry-once guard');
    expectEqual(refreshCount, 2, 'refresh ran once more then stopped at _retried guard');

    // 20c. Transport-level retry wrapper for transient SocketException (NetworkError).
    var netAttempts = 0;
    var alwaysOffline = false;
    final HttpTransport retryingTransport = HttpTransport.fromHandler((_) async {
      for (var attempt = 0;; attempt++) {
        netAttempts++;
        try {
          if (alwaysOffline || netAttempts == 1) {
            throw const SocketException('transient reset');
          }
          return RawHttpResponse.json(<String, dynamic>{'id': '1', 'name': 'Online'});
        } on SocketException {
          if (attempt >= 1) rethrow;
        }
      }
    });
    final TukanClient netRetryClient = TukanClient(
      TukanClientConfig(baseUrl: 'https://api.example.test', transport: retryingTransport),
    );
    final ApiResult<UserModel, Object?> netOk =
        await netRetryClient.get<UserModel>('/net', fromJson: UserModel.fromJson);
    expectEqual(netOk.data?.name, 'Online', 'transport retry recovers transient SocketException');
    expectEqual(netAttempts, 2, 'transport retried once');

    alwaysOffline = true;
    final ApiResult<UserModel, Object?> netFail =
        await netRetryClient.get<UserModel>('/net', fromJson: UserModel.fromJson);
    expectTrue(netFail.error is NetworkError<Object?>, 'exhausted transport retry yields NetworkError');
    passed++;
  }

  // 21. R10 & R11: Mid-flight CancelToken, Duration.zero timeout, precedence, loopback files & close() ownership.
  {
    final TukanClient pendingClient = TukanClient(
      TukanClientConfig(
        baseUrl: 'https://api.example.test',
        timeout: const Duration(seconds: 5),
        transport: HttpTransport.fromHandler((_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return RawHttpResponse.empty();
        }),
      ),
    );

    final CancelToken midToken = CancelToken();
    Timer(const Duration(milliseconds: 15), () => midToken.cancel('navigated away'));
    final ApiResult<void, Object?> midCancelled = await pendingClient.get<void>(
      '/slow',
      cancelToken: midToken,
    );
    expectTrue(
      midCancelled.error is CancelledError<Object?> &&
          (midCancelled.error as CancelledError<Object?>).reason == 'navigated away',
      'mid-flight CancelToken resolves promptly with reason',
    );

    final ApiResult<void, Object?> zeroTimeout = await pendingClient.get<void>(
      '/slow',
      timeout: Duration.zero,
    );
    expectTrue(zeroTimeout.error is TimeoutError<Object?>, 'Duration.zero triggers immediate TimeoutError');

    final CancelToken preCancelled = CancelToken()..cancel('already gone');
    final ApiResult<void, Object?> precedenceRes = await pendingClient.get<void>(
      '/slow',
      cancelToken: preCancelled,
      timeout: Duration.zero,
    );
    expectTrue(
      precedenceRes.error is CancelledError<Object?> &&
          (precedenceRes.error as CancelledError<Object?>).reason == 'already gone',
      'pre-cancelled CancelToken takes precedence over Duration.zero timeout',
    );

    final ApiResult<void, Object?> overrideTimeout = await pendingClient.get<void>(
      '/slow',
      timeout: const Duration(milliseconds: 20),
    );
    expectTrue(
      overrideTimeout.error is TimeoutError<Object?> &&
          (overrideTimeout.error as TimeoutError<Object?>).timeout == const Duration(milliseconds: 20),
      'per-request timeout overrides larger config.timeout',
    );

    // Transport ownership: client.close() must NOT close externally provided transport.
    var externalClosed = false;
    final HttpTransport externalTransport = HttpTransport.fromHandler(
      (_) => RawHttpResponse.empty(),
      onClose: () => externalClosed = true,
    );
    final TukanClient borrowedClient = TukanClient(
      TukanClientConfig(baseUrl: 'https://api.example.test', transport: externalTransport),
    );
    borrowedClient.close();
    expectEqual(externalClosed, false, 'client.close() does not close external transport');
    externalTransport.close();
    expectEqual(externalClosed, true, 'explicit externalTransport.close() still works');

    // Real dart:io loopback binary download & mid-flight CancelToken socket abort.
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final TukanClient ioClient = TukanClient(
      TukanClientConfig(baseUrl: 'http://127.0.0.1:${server.port}'),
    );
    final StreamSubscription<HttpRequest> sub = server.listen((HttpRequest req) async {
      if (req.uri.path == '/file.bin') {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary
          ..add(<int>[9, 8, 7, 6]);
        await req.response.close();
        return;
      }
      if (req.uri.path == '/hold') {
        await Future<void>.delayed(const Duration(seconds: 2));
        req.response.statusCode = HttpStatus.ok;
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    });

    try {
      final ApiResult<Uint8List, Object?> dlRes =
          await ioClient.get<Uint8List>('/file.bin', decode: Decoders.bytes);
      expectDeepEqual(dlRes.data, <int>[9, 8, 7, 6], 'loopback binary Uint8List download succeeds');

      final CancelToken socketToken = CancelToken();
      Timer(const Duration(milliseconds: 25), () => socketToken.cancel('socket cancelled'));
      final ApiResult<void, Object?> abortedSocket =
          await ioClient.get<void>('/hold', cancelToken: socketToken);
      expectTrue(
        abortedSocket.error is CancelledError<Object?> &&
            (abortedSocket.error as CancelledError<Object?>).reason == 'socket cancelled',
        'loopback mid-flight CancelToken aborts real socket',
      );
    } finally {
      ioClient.close();
      await sub.cancel();
      await server.close(force: true);
    }
    passed++;
  }

  print('client-dart tests passed ($passed cases)');
}
