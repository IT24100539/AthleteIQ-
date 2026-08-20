import 'package:athleteiq/utils/friendly_error.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('friendlyError', () {
    test('maps permission-denied strings', () {
      expect(
        friendlyError(Exception('PERMISSION_DENIED: missing or insufficient permissions')),
        'You do not have access to this data.',
      );
    });

    test('maps network / timeout strings', () {
      expect(
        friendlyError('SocketException: Failed host lookup'),
        'Network error. Check your connection and try again.',
      );
      expect(
        friendlyError('TimeoutException: timed out'),
        'Network error. Check your connection and try again.',
      );
    });

    test('keeps RiskEngineException message', () {
      expect(
        friendlyError(const RiskEngineException('Could not update the risk score.')),
        'Could not update the risk score.',
      );
    });

    test('maps FirebaseFunctionsException codes', () {
      expect(
        friendlyError(
          FirebaseFunctionsException(code: 'unavailable', message: 'UNAVAILABLE'),
        ),
        'The service is temporarily unavailable. Check your connection and try again.',
      );
      expect(
        friendlyError(
          FirebaseFunctionsException(code: 'unauthenticated', message: 'UNAUTHENTICATED'),
        ),
        'Please sign in again, then retry.',
      );
    });
  });
}
