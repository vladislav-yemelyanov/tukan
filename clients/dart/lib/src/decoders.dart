import 'dart:convert';
import 'dart:typed_data';

typedef JsonFactory<T> = T Function(Map<String, dynamic> json);
typedef ResponseDecoder<T> = T Function(Object? data);

/// Reusable decoders for top-level JSON collections and primitives returned by OpenAPI endpoints.
abstract final class Decoders {
  static ResponseDecoder<List<T>> list<T>(JsonFactory<T> fromJson) {
    return (Object? data) {
      if (data is! List) {
        throw FormatException('Expected JSON array, got ${data.runtimeType}');
      }

      return <T>[
        for (final Object? item in data)
          if (item is Map)
            fromJson(Map<String, dynamic>.from(item))
          else
            throw FormatException('Expected JSON object item in array, got ${item.runtimeType}'),
      ];
    };
  }

  static ResponseDecoder<List<T>> enumList<T>(T Function(Object? json) fromJson) {
    return (Object? data) {
      if (data is! List) {
        throw FormatException('Expected JSON array, got ${data.runtimeType}');
      }

      return <T>[for (final Object? item in data) fromJson(item)];
    };
  }

  static ResponseDecoder<List<T>> primitiveList<T>() {
    return (Object? data) {
      if (data is! List) {
        throw FormatException('Expected JSON array, got ${data.runtimeType}');
      }

      return <T>[
        for (final Object? item in data)
          if (item is T)
            item
          else
            throw FormatException('Expected list item of type $T, got ${item.runtimeType}'),
      ];
    };
  }

  static ResponseDecoder<Map<String, T>> map<T>(JsonFactory<T> fromJson) {
    return (Object? data) {
      if (data is! Map) {
        throw FormatException('Expected JSON object, got ${data.runtimeType}');
      }

      final Map<String, T> result = <String, T>{};
      for (final MapEntry<Object?, Object?> entry in data.entries) {
        final Object? key = entry.key;
        final Object? value = entry.value;
        if (key is! String || value is! Map) {
          throw FormatException(
            'Expected string key and object value in map, got ${key.runtimeType}: ${value.runtimeType}',
          );
        }
        result[key] = fromJson(Map<String, dynamic>.from(value));
      }
      return result;
    };
  }

  static String string(Object? data) {
    if (data is String) return data;
    throw FormatException('Expected String response, got ${data.runtimeType}');
  }

  static int integer(Object? data) {
    if (data is int) return data;
    throw FormatException('Expected int response, got ${data.runtimeType}');
  }

  static num number(Object? data) {
    if (data is num) return data;
    throw FormatException('Expected num response, got ${data.runtimeType}');
  }

  static bool boolean(Object? data) {
    if (data is bool) return data;
    throw FormatException('Expected bool response, got ${data.runtimeType}');
  }

  static Uint8List bytes(Object? data) {
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is String) return Uint8List.fromList(utf8.encode(data));
    throw FormatException('Expected binary response, got ${data.runtimeType}');
  }
}
