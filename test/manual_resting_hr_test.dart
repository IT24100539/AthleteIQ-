import 'package:athleteiq/models/athlete.dart';
import 'package:athleteiq/models/checkin.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AthleteProfile.allowsManualRestingHr', () {
    AthleteProfile profile(String tier) => AthleteProfile(
          uid: 'a1',
          name: 'Test',
          createdAt: DateTime(2026, 1, 1),
          deviceTier: tier,
        );

    test('Tier 3 can enter resting HR by hand', () {
      expect(profile('tier3').allowsManualRestingHr, isTrue);
    });

    test('missing deviceTier defaults to Tier 3', () {
      final parsed = AthleteProfile.fromMap('a1', {
        'name': 'Test',
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(parsed.deviceTier, 'tier3');
      expect(parsed.allowsManualRestingHr, isTrue);
    });

    test('Tier 1 and Tier 2 stay on device resting HR', () {
      expect(profile('tier1').allowsManualRestingHr, isFalse);
      expect(profile('tier2').allowsManualRestingHr, isFalse);
    });
  });

  group('CheckIn.toMap resting HR / HRV', () {
    test('omits restingHeartRate and hrv when not entered', () {
      final map = CheckIn(
        id: '',
        date: DateTime(2026, 8, 16),
        fatigueScore: 3,
        sleepHours: 7,
      ).toMap();

      expect(map.containsKey('restingHeartRate'), isFalse);
      expect(map.containsKey('hrv'), isFalse);
      expect(map['sleepHours'], 7);
      expect(map['date'], isA<Timestamp>());
    });

    test('writes resting HR without inventing HRV', () {
      final map = CheckIn(
        id: '',
        date: DateTime(2026, 8, 16),
        fatigueScore: 3,
        sleepHours: 7,
        restingHeartRate: 58,
      ).toMap();

      expect(map['restingHeartRate'], 58);
      expect(map.containsKey('hrv'), isFalse);
    });

    test('writes optional manual resting HR and HRV when entered', () {
      final map = CheckIn(
        id: '',
        date: DateTime(2026, 8, 16),
        fatigueScore: 3,
        sleepHours: 7,
        restingHeartRate: 58,
        hrv: 62,
      ).toMap();

      expect(map['restingHeartRate'], 58);
      expect(map['hrv'], 62);
    });
  });
}
