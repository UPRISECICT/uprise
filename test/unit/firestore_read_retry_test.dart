import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uprise/services/firestore_read_retry.dart';

void main() {
  test('remounted widgets receive the initial data again', () async {
    final stream = retryFirestoreStream(() => Stream.value(4));
    expect(await stream.toList(), [4]);
    expect(await stream.toList(), [4]);
  });

  final unavailable = FirebaseException(
    plugin: 'cloud_firestore',
    code: 'unavailable',
  );

  test(
    'reopens a failed initial listener and receives existing data',
    () async {
      var attempts = 0;
      final values = await retryFirestoreStream(() {
        attempts++;
        return attempts < 3
            ? Stream<int>.error(unavailable)
            : Stream<int>.value(12);
      }, retryDelay: Duration.zero).toList();
      expect(values, [12]);
      expect(attempts, 3);
    },
  );

  test('persistent permission errors surface after bounded retries', () async {
    var attempts = 0;
    final denied = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    await expectLater(
      retryFirestoreStream<int>(() {
        attempts++;
        return Stream.error(denied);
      }, retryDelay: Duration.zero).toList(),
      throwsA(same(denied)),
    );
    expect(attempts, 3);
  });

  test('one-shot reads recover without caching an empty fallback', () async {
    var attempts = 0;
    final count = await retryFirestoreRead(() async {
      if (++attempts < 2) throw unavailable;
      return 7;
    }, retryDelay: Duration.zero);
    expect(count, 7);
    expect(attempts, 2);
  });

  test('non-transient errors are not retried', () async {
    var attempts = 0;
    await expectLater(
      retryFirestoreRead<int>(() async {
        attempts++;
        throw StateError('invalid data');
      }, retryDelay: Duration.zero),
      throwsStateError,
    );
    expect(attempts, 1);
  });
}
