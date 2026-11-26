/// Case-insensitive HTTP headers container backed by lowercase header names.
final class HttpHeadersMap {
  final Map<String, String> _entries = <String, String>{};

  HttpHeadersMap([Map<String, String>? initial]) {
    if (initial != null) {
      for (final MapEntry<String, String> entry in initial.entries) {
        _entries[entry.key.toLowerCase()] = entry.value;
      }
    }
  }

  HttpHeadersMap.from(HttpHeadersMap other) {
    _entries.addAll(other._entries);
  }

  String? operator [](String name) => _entries[name.toLowerCase()];

  void operator []=(String name, String value) {
    _entries[name.toLowerCase()] = value;
  }

  String? get(String name) => _entries[name.toLowerCase()];

  void set(String name, String value) {
    _entries[name.toLowerCase()] = value;
  }

  String? remove(String name) => _entries.remove(name.toLowerCase());

  bool containsKey(String name) => _entries.containsKey(name.toLowerCase());

  bool get isEmpty => _entries.isEmpty;

  bool get isNotEmpty => _entries.isNotEmpty;

  Iterable<MapEntry<String, String>> get entries => _entries.entries;

  Map<String, String> toMap() => Map<String, String>.unmodifiable(_entries);

  HttpHeadersMap copy() => HttpHeadersMap.from(this);
}
