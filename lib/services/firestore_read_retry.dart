import 'package:cloud_firestore/cloud_firestore.dart';

bool _canRetry(Object error) =>
    error is FirebaseException &&
    const {
      'unavailable',
      'deadline-exceeded',
      'aborted',
      'unauthenticated',
      'permission-denied',
    }.contains(error.code);

/// Reopens failed reads during login without hiding persistent access errors.
/// Permission failures are retried briefly because auth may still be settling.
Stream<T> retryFirestoreStream<T>(
  Stream<T> Function() open, {
  Duration retryDelay = const Duration(milliseconds: 500),
}) => Stream<T>.multi((controller) {
  // Each mount gets its own initial snapshot, including after layout changes.
  final subscription = _retryStream(open, retryDelay: retryDelay).listen(
    controller.addSync,
    onError: controller.addErrorSync,
    onDone: controller.closeSync,
  );
  controller.onCancel = subscription.cancel;
});

Stream<T> _retryStream<T>(
  Stream<T> Function() open, {
  required Duration retryDelay,
}) async* {
  for (var attempt = 0; ; attempt++) {
    try {
      await for (final value in open()) {
        yield value;
      }
      return;
    } catch (error) {
      if (attempt >= 2 || !_canRetry(error)) rethrow;
      await Future<void>.delayed(retryDelay * (attempt + 1));
    }
  }
}

Future<T> retryFirestoreRead<T>(
  Future<T> Function() read, {
  Duration retryDelay = const Duration(milliseconds: 500),
}) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await read();
    } catch (error) {
      if (attempt >= 2 || !_canRetry(error)) rethrow;
      await Future<void>.delayed(retryDelay * (attempt + 1));
    }
  }
}
