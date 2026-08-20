import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'empty_state.dart';

/// Full-screen loading spinner used while a Firestore stream has not emitted.
const Widget kAsyncLoading = Center(
  child: CircularProgressIndicator(color: AppColors.mint),
);

/// Returns a loading or error widget, or `null` when [snapshot] is ready.
///
/// Treats a stream that has already emitted `null` (`RiskResult?`) as loaded:
/// `connectionState` is `active` even when `hasData` is false.
Widget? asyncBody(
  AsyncSnapshot snapshot, {
  required String heading,
}) {
  if (snapshot.hasError) {
    return asyncError(heading: heading, error: snapshot.error);
  }
  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
    return kAsyncLoading;
  }
  return null;
}

/// Like [asyncBody] for nested StreamBuilders — first error wins; wait until
/// every snapshot has left the initial waiting state (or already has data).
Widget? asyncBodyAny(
  Iterable<AsyncSnapshot> snapshots, {
  required String heading,
}) {
  for (final snapshot in snapshots) {
    if (snapshot.hasError) {
      return asyncError(heading: heading, error: snapshot.error);
    }
  }
  final stillWaiting = snapshots.any(
    (s) => s.connectionState == ConnectionState.waiting && !s.hasData,
  );
  if (stillWaiting) return kAsyncLoading;
  return null;
}

Widget asyncError({required String heading, Object? error}) {
  return Center(
    child: EmptyState(
      icon: Icons.cloud_off_outlined,
      heading: heading,
      subtext: friendlyError(error),
      warn: true,
    ),
  );
}

/// Prevents an uncaught stream error from crashing the app. Secondary
/// `.listen()` subscriptions (roster risk, inbox last-read) use this.
void ignoreStreamError(Object error, [StackTrace? stackTrace]) {
  debugPrint('Stream error: $error');
}
