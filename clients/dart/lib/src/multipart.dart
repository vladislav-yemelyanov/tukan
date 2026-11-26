import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'serialization.dart';

/// Binary file payload for `multipart/form-data` requests.
final class MultipartFile {
  final Uint8List bytes;
  final String? filename;
  final String? contentType;

  const MultipartFile(
    this.bytes, {
    this.filename,
    this.contentType,
  });

  factory MultipartFile.fromBytes(
    List<int> bytes, {
    String? filename,
    String? contentType,
  }) =>
      MultipartFile(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        filename: filename,
        contentType: contentType,
      );

  factory MultipartFile.fromString(
    String content, {
    String? filename,
    String? contentType,
  }) =>
      MultipartFile(
        Uint8List.fromList(utf8.encode(content)),
        filename: filename,
        contentType: contentType ?? 'text/plain; charset=utf-8',
      );
}

/// Explicit container for `multipart/form-data` request fields.
final class MultipartBody {
  final Map<String, Object?> fields;

  const MultipartBody(this.fields);
}

/// Encoded RFC 7578 multipart payload with its `Content-Type` boundary header.
final class EncodedMultipart {
  final Uint8List bytes;
  final String contentType;

  const EncodedMultipart(this.bytes, this.contentType);
}

final Random _boundaryRandom = Random();

String _generateBoundary() {
  final String partA = _boundaryRandom.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
  final String partB = _boundaryRandom.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
  return '----TukanBoundary$partA$partB';
}

String _escapeDispositionValue(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\r', '').replaceAll('\n', '');

void _writeAscii(BytesBuilder builder, String text) {
  builder.add(utf8.encode(text));
}

void _appendMultipartEntry(BytesBuilder builder, String boundary, String name, Object? value) {
  if (value == null) return;

  final String safeName = _escapeDispositionValue(name);

  if (value is MultipartFile) {
    _writeAscii(builder, '--$boundary\r\n');
    final String filenamePart =
        value.filename != null ? '; filename="${_escapeDispositionValue(value.filename!)}"' : '';
    _writeAscii(builder, 'Content-Disposition: form-data; name="$safeName"$filenamePart\r\n');
    _writeAscii(builder, 'Content-Type: ${value.contentType ?? 'application/octet-stream'}\r\n\r\n');
    builder.add(value.bytes);
    _writeAscii(builder, '\r\n');
    return;
  }

  if (value is Uint8List || value is List<int>) {
    final List<int> rawBytes = value as List<int>;
    _writeAscii(builder, '--$boundary\r\n');
    _writeAscii(builder, 'Content-Disposition: form-data; name="$safeName"; filename="$safeName"\r\n');
    _writeAscii(builder, 'Content-Type: application/octet-stream\r\n\r\n');
    builder.add(rawBytes);
    _writeAscii(builder, '\r\n');
    return;
  }

  if (value is List<Object?>) {
    for (final Object? item in value) {
      if (item != null) {
        _appendMultipartEntry(builder, boundary, name, item);
      }
    }
    return;
  }

  final Object? unwrapped = unwrapJsonEncodable(value);
  if (unwrapped == null) return;

  if (unwrapped is String || unwrapped is num || unwrapped is bool) {
    _writeAscii(builder, '--$boundary\r\n');
    _writeAscii(builder, 'Content-Disposition: form-data; name="$safeName"\r\n\r\n');
    builder.add(utf8.encode(unwrapped.toString()));
    _writeAscii(builder, '\r\n');
    return;
  }

  if (unwrapped is DateTime) {
    _writeAscii(builder, '--$boundary\r\n');
    _writeAscii(builder, 'Content-Disposition: form-data; name="$safeName"\r\n\r\n');
    builder.add(utf8.encode(unwrapped.toIso8601String()));
    _writeAscii(builder, '\r\n');
    return;
  }

  _writeAscii(builder, '--$boundary\r\n');
  _writeAscii(builder, 'Content-Disposition: form-data; name="$safeName"\r\n');
  _writeAscii(builder, 'Content-Type: application/json\r\n\r\n');
  builder.add(utf8.encode(jsonEncode(unwrapped)));
  _writeAscii(builder, '\r\n');
}

/// Serializes [fields] into a `multipart/form-data` payload.
EncodedMultipart encodeMultipart(Map<String, Object?> fields) {
  final String boundary = _generateBoundary();
  final BytesBuilder builder = BytesBuilder(copy: false);

  for (final MapEntry<String, Object?> entry in fields.entries) {
    _appendMultipartEntry(builder, boundary, entry.key, entry.value);
  }

  _writeAscii(builder, '--$boundary--\r\n');
  return EncodedMultipart(builder.takeBytes(), 'multipart/form-data; boundary=$boundary');
}
