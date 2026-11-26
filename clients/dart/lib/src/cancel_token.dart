import 'dart:async';

/// Exception thrown or attached as [ApiError.cause] when a request is cancelled via [CancelToken].
final class ApiCancelledException implements Exception {
  final Object? reason;

  const ApiCancelledException([this.reason]);

  @override
  String toString() =>
      reason == null ? 'ApiCancelledException: Request cancelled' : 'ApiCancelledException: $reason';
}

/// Cooperative cancellation signal for in-flight HTTP requests.
final class CancelToken {
  bool _isCancelled = false;
  Object? _reason;
  final Completer<Object?> _completer = Completer<Object?>();
  final List<void Function(Object? reason)> _listeners = <void Function(Object? reason)>[];

  bool get isCancelled => _isCancelled;

  Object? get reason => _reason;

  Future<Object?> get whenCancelled => _completer.future;

  /// Cancels the token with an optional [reason]. Subsequent calls are ignored.
  void cancel([Object? reason]) {
    if (_isCancelled) return;

    _isCancelled = true;
    _reason = reason;
    if (!_completer.isCompleted) {
      _completer.complete(reason);
    }

    final List<void Function(Object? reason)> snapshot =
        List<void Function(Object? reason)>.of(_listeners);
    for (final void Function(Object? reason) listener in snapshot) {
      try {
        listener(reason);
      } catch (_) {
        // Cancellation listeners must not prevent remaining listeners from running.
      }
    }
  }

  /// Registers a [listener] invoked on cancellation (or immediately if already cancelled)
  /// and returns an unsubscribe callback.
  void Function() addListener(void Function(Object? reason) listener) {
    if (_isCancelled) {
      listener(_reason);
      return () {};
    }

    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }
}
