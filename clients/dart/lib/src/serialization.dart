import 'dart:convert';
import 'dart:typed_data';

import 'headers.dart';
import 'multipart.dart';

/// Raised internally when request URI, headers, cookies, or body cannot be serialized.
final class RequestBuildException implements Exception {
  final String message;

  const RequestBuildException(this.message);

  @override
  String toString() => message;
}

String normalizeMimeType(String contentType) {
  final int semi = contentType.indexOf(';');
  final String raw = semi == -1 ? contentType : contentType.substring(0, semi);
  return raw.trim().toLowerCase();
}

bool isJsonMimeType(String mime) =>
    mime == 'application/json' || (mime.startsWith('application/') && mime.endsWith('+json'));

/// Bridges Tukan-generated models and enums (which expose `toJson()` without
/// importing any client library) into plain maps or primitive values.
Object? unwrapJsonEncodable(Object? value) {
  if (value == null ||
      value is String ||
      value is num ||
      value is bool ||
      value is DateTime ||
      value is Uint8List ||
      value is List<Object?> ||
      value is Map<Object?, Object?> ||
      value is MultipartFile ||
      value is MultipartBody) {
    return value;
  }

  try {
    return (value as dynamic).toJson();
  } on NoSuchMethodError {
    return value;
  }
}

Map<String, Object?>? toParamsMap(Object? source, String label) {
  if (source == null) return null;

  if (source is HttpHeadersMap) {
    return Map<String, Object?>.from(source.toMap());
  }

  final Object? unwrapped = unwrapJsonEncodable(source);
  if (unwrapped is Map<Object?, Object?>) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in unwrapped.entries)
        entry.key.toString(): entry.value,
    };
  }

  throw RequestBuildException('$label must be a Map or a Tukan model with toJson()');
}

String serializeParamValue(Object value) {
  final Object? unwrapped = unwrapJsonEncodable(value);
  if (unwrapped is DateTime) {
    return unwrapped.toIso8601String();
  }

  if (unwrapped is Map<Object?, Object?> || unwrapped is List<Object?>) {
    return jsonEncode(unwrapped);
  }

  return unwrapped.toString();
}

String encodeSearchParams(Map<String, Object?> record) {
  final List<String> pairs = <String>[];

  for (final MapEntry<String, Object?> entry in record.entries) {
    final Object? value = entry.value;
    if (value == null) continue;

    final String encodedKey = Uri.encodeQueryComponent(entry.key);
    if (value is List<Object?>) {
      for (final Object? item in value) {
        if (item != null) {
          pairs.add('$encodedKey=${Uri.encodeQueryComponent(serializeParamValue(item))}');
        }
      }
    } else {
      pairs.add('$encodedKey=${Uri.encodeQueryComponent(serializeParamValue(value))}');
    }
  }

  return pairs.join('&');
}

final RegExp _pathParamPattern = RegExp(r'\{([^}]+)\}');

Uri buildRequestUri(
  String baseUrl,
  String template, {
  Object? pathParams,
  Object? query,
}) {
  final Map<String, Object?>? resolvedPathParams = toParamsMap(pathParams, 'pathParams');

  final String resolvedPath = template.replaceAllMapped(_pathParamPattern, (Match match) {
    final String key = match.group(1)!;
    final Object? value = resolvedPathParams?[key];
    if (value == null) {
      throw RequestBuildException('Missing required path parameter "$key" for $template');
    }

    return Uri.encodeComponent(serializeParamValue(value));
  });

  final String normalizedBase = baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final String pathPart =
      normalizedBase.isNotEmpty && !resolvedPath.startsWith('/') ? '/$resolvedPath' : resolvedPath;

  var url = '$normalizedBase$pathPart';

  final Map<String, Object?>? queryMap = toParamsMap(query, 'query');
  if (queryMap != null) {
    final String queryString = encodeSearchParams(queryMap);
    if (queryString.isNotEmpty) {
      url += (url.contains('?') ? '&' : '?') + queryString;
    }
  }

  return Uri.parse(url);
}

void _applyHeaders(HttpHeadersMap target, Object? source, String label) {
  if (source == null) return;

  if (source is HttpHeadersMap) {
    for (final MapEntry<String, String> entry in source.entries) {
      target.set(entry.key, entry.value);
    }
    return;
  }

  final Map<String, Object?>? map = toParamsMap(source, label);
  if (map == null) return;

  for (final MapEntry<String, Object?> entry in map.entries) {
    final Object? value = entry.value;
    if (value == null) continue;

    if (value is List<Object?>) {
      final List<String> items = <String>[
        for (final Object? item in value)
          if (item != null) serializeParamValue(item),
      ];
      if (items.isNotEmpty) {
        target.set(entry.key, items.join(', '));
      }
    } else {
      target.set(entry.key, serializeParamValue(value));
    }
  }
}

({HttpHeadersMap headers, bool hasRequestContentType}) buildRequestHeaders(
  Object? staticBaseHeaders,
  Object? dynamicBaseHeaders,
  Object? requestHeaders,
  Object? cookies,
) {
  final HttpHeadersMap headers = HttpHeadersMap();
  _applyHeaders(headers, staticBaseHeaders, 'config.headers');
  _applyHeaders(headers, dynamicBaseHeaders, 'headersProvider');

  final HttpHeadersMap perRequest = HttpHeadersMap();
  _applyHeaders(perRequest, requestHeaders, 'headers');
  final bool hasRequestContentType = perRequest.containsKey('content-type');
  for (final MapEntry<String, String> entry in perRequest.entries) {
    headers.set(entry.key, entry.value);
  }

  final Map<String, Object?>? cookieMap = toParamsMap(cookies, 'cookie');
  if (cookieMap != null) {
    final List<String> pairs = <String>[];
    for (final MapEntry<String, Object?> entry in cookieMap.entries) {
      if (entry.value != null) {
        pairs.add('${entry.key}=${Uri.encodeComponent(serializeParamValue(entry.value!))}');
      }
    }

    if (pairs.isNotEmpty) {
      final String? existing = headers.get('cookie');
      final String joined = pairs.join('; ');
      headers.set('cookie', existing == null || existing.isEmpty ? joined : '$existing; $joined');
    }
  }

  return (headers: headers, hasRequestContentType: hasRequestContentType);
}

Object? mergeHeaderOverrides(Map<String, dynamic>? base, Object? override) {
  if (base == null) return override;
  if (override == null) return base;

  final HttpHeadersMap merged = HttpHeadersMap();
  _applyHeaders(merged, base, 'operation.headers');
  _applyHeaders(merged, override, 'headers');
  return merged;
}

Object? mergeParamOverrides(Map<String, dynamic>? base, Object? override, String label) {
  if (base == null) return override;
  if (override == null) return base;

  final Map<String, Object?> merged = Map<String, Object?>.of(base);
  final Map<String, Object?>? extra = toParamsMap(override, label);
  if (extra != null) {
    merged.addAll(extra);
  }
  return merged;
}

void _applyContentType(
  HttpHeadersMap headers,
  String? explicitContentType,
  String fallbackContentType,
  bool hasRequestContentType,
) {
  if (explicitContentType != null && !hasRequestContentType) {
    headers.set('content-type', explicitContentType);
    return;
  }

  if (!headers.containsKey('content-type')) {
    headers.set('content-type', fallbackContentType);
  }
}

Uint8List? serializeRequestBody(
  Object? body,
  String? contentType,
  HttpHeadersMap headers,
  bool hasRequestContentType,
) {
  if (body == null) return null;

  if (body is MultipartBody) {
    final EncodedMultipart encoded = encodeMultipart(body.fields);
    headers.set('content-type', encoded.contentType);
    return encoded.bytes;
  }

  final String effectiveMime =
      normalizeMimeType(contentType ?? headers.get('content-type') ?? 'application/json');

  if (effectiveMime == 'multipart/form-data') {
    final Map<String, Object?>? fields = toParamsMap(body, 'multipart/form-data body');
    final EncodedMultipart encoded = encodeMultipart(fields ?? const <String, Object?>{});
    headers.set('content-type', encoded.contentType);
    return encoded.bytes;
  }

  if (effectiveMime == 'application/x-www-form-urlencoded') {
    _applyContentType(
      headers,
      contentType,
      'application/x-www-form-urlencoded',
      hasRequestContentType,
    );
    if (body is String) {
      return Uint8List.fromList(utf8.encode(body));
    }

    final Map<String, Object?>? params = toParamsMap(
      body,
      'application/x-www-form-urlencoded body',
    );
    return Uint8List.fromList(utf8.encode(encodeSearchParams(params ?? const <String, Object?>{})));
  }

  if (isJsonMimeType(effectiveMime)) {
    _applyContentType(headers, contentType, 'application/json', hasRequestContentType);
    return Uint8List.fromList(utf8.encode(jsonEncode(body)));
  }

  if (contentType != null && !hasRequestContentType) {
    headers.set('content-type', contentType);
  }

  if (body is Uint8List) return body;
  if (body is List<int>) return Uint8List.fromList(body);
  if (body is String) return Uint8List.fromList(utf8.encode(body));

  throw RequestBuildException('Unsupported request body type ${body.runtimeType} for $effectiveMime');
}
