import 'package:athleteiq/models/risk_latest.dart';
import 'package:athleteiq/utils/wearable_sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calibrationProgressLabel', () {
    test('uses the pipeline threshold of 5', () {
      expect(calibrationProgressLabel(0), '0 of 5 check-ins needed to calibrate');
      expect(calibrationProgressLabel(3), '3 of 5 check-ins needed to calibrate');
    });
  });

  group('notEnoughDataSubtext', () {
    test('includes join age and check-in count', () {
      final text = notEnoughDataSubtext(
        checkInCount: 3,
        joinedAt: DateTime(2026, 8, 13),
        now: DateTime(2026, 8, 15),
      );
      expect(text, contains('This athlete joined 2 days ago.'));
      expect(text, contains('3 of 5 check-ins needed to calibrate'));
      expect(text, isNot(contains('LOW')));
    });
  });

  group('findWearableSyncIssue', () {
    test('uses lastSyncError when present', () {
      final issue = findWearableSyncIssue({
        'apple_watch': {
          'connected': true,
          'name': 'Apple Watch',
          'lastSyncError': 'Could not read HealthKit: denied',
          'lastSync': '2026-08-15T10:00:00.000',
        },
      });
      expect(issue, isNotNull);
      expect(issue!.deviceName, 'Apple Watch');
      expect(issue.message, 'Could not read HealthKit: denied');
    });

    test('matches nightly never-synced copy', () {
      final issue = findWearableSyncIssue({
        'apple_watch': {'connected': true, 'name': 'Apple Watch'},
      });
      expect(issue!.message, 'apple_watch has never completed a sync.');
    });

    test('matches nightly stale-sync copy', () {
      final issue = findWearableSyncIssue(
        {
          'apple_watch': {
            'connected': true,
            'lastSync': '2026-08-10T10:00:00.000',
          },
        },
        now: DateTime.parse('2026-08-15T10:00:00.000'),
      );
      expect(issue!.message, 'apple_watch last synced more than 2 days ago.');
    });

    test('skips disconnected devices', () {
      final issue = findWearableSyncIssue({
        'apple_watch': {
          'connected': false,
          'lastSyncError': 'Could not read HealthKit: x',
        },
      });
      expect(issue, isNull);
    });

    test('skips manual Tier 3 metrics doc', () {
      final issue = findWearableSyncIssue({
        'manual_tier3': {
          'connected': true,
          'name': 'Manual entry',
          'tier': 'tier3',
        },
      });
      expect(issue, isNull);
    });

    test('empty-day is not a failure', () {
      expect(isHealthKitReadFailureNote(null), isFalse);
      expect(isHealthKitReadFailureNote(''), isFalse);
      expect(
        isHealthKitReadFailureNote('Could not read HealthKit: boom'),
        isTrue,
      );
      expect(
        isHealthKitReadFailureNote('HealthKit is only available on a physical iPhone.'),
        isTrue,
      );
      expect(
        isWearableReadFailureNote(
          'Health Connect is not installed on this phone. Install it from the Play Store.',
        ),
        isTrue,
      );
      expect(
        isWearableReadFailureNote('Could not read Health Connect: denied'),
        isTrue,
      );
      expect(
        isWearableReadFailureNote('Health Connect needs an update. Open the Play Store'),
        isTrue,
      );
    });
  });
}
