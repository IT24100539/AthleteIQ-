import 'dart:async';

import 'package:flutter/foundation.dart';

/// If a Firestore listen is denied or drops, emit [fallback] instead of
/// killing the screen.
///
/// Cancel is deferred one microtask so Flutter web's `onSnapshot` can
/// finish assigning `onSnapshotUnsubscribe` (otherwise stopListen throws
/// LateInitializationError).
Stream<T> emitOnError<T>(Stream<T> source, T fallback) {
  StreamController<T>? controller;
  StreamSubscription<T>? sub;

  controller = StreamController<T>(
    onListen: () {
      sub = source.listen(
        (value) {
          if (!(controller?.isClosed ?? true)) controller!.add(value);
        },
        onError: (Object error, StackTrace stack) {
          debugPrint('Firestore stream error (fallback): $error');
          if (!(controller?.isClosed ?? true)) controller!.add(fallback);
        },
        onDone: () {
          if (!(controller?.isClosed ?? true)) controller!.close();
        },
      );
    },
    onCancel: () async {
      await Future<void>.delayed(Duration.zero);
      await sub?.cancel();
    },
  );

  return controller.stream;
}
