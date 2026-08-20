import 'package:cloud_functions/cloud_functions.dart';

/// User-facing error when `recalculateRisk` fails after data was already saved.
class RiskEngineException implements Exception {
  final String message;
  const RiskEngineException(this.message);

  @override
  String toString() => message;
}

/// Maps Firebase / network failures to a short sentence the athlete or coach
/// can act on. Never dump raw exception types or stack traces into the UI.
String friendlyError(Object? error) {
  if (error is RiskEngineException) return error.message;
  if (error is FirebaseFunctionsException) {
    return friendlyFunctionsMessage(error);
  }

  final raw = error?.toString() ?? '';
  final s = raw.toLowerCase();

  if (s.contains('permission-denied') || s.contains('permission_denied')) {
    return 'You do not have access to this data.';
  }
  if (s.contains('unauthenticated')) {
    return 'Please sign in again, then retry.';
  }
  if (s.contains('unavailable') ||
      s.contains('deadline-exceeded') ||
      s.contains('socketexception') ||
      s.contains('network') ||
      s.contains('timed out') ||
      s.contains('timeout')) {
    return 'Network error. Check your connection and try again.';
  }
  if (s.contains('not-found') || s.contains('not_found')) {
    return 'That record was not found.';
  }

  final stripped = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  if (stripped.isNotEmpty && stripped.length < 180 && !stripped.contains('\n')) {
    return stripped;
  }
  return 'Something went wrong. Try again in a moment.';
}

String friendlyFunctionsMessage(FirebaseFunctionsException e) {
  switch (e.code) {
    case 'unauthenticated':
      return 'Please sign in again, then retry.';
    case 'permission-denied':
      return 'You do not have access to do that.';
    case 'unavailable':
    case 'deadline-exceeded':
      return 'The service is temporarily unavailable. Check your connection and try again.';
    case 'not-found':
      return 'That record was not found.';
    case 'invalid-argument':
      final msg = e.message?.trim();
      if (msg != null && msg.isNotEmpty) return msg;
      return 'Something about that request was invalid.';
    default:
      final msg = e.message?.trim();
      if (msg != null && msg.isNotEmpty && msg.length < 180) return msg;
      return 'Something went wrong. Try again in a moment.';
  }
}
