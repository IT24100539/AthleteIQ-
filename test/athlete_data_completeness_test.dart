import 'package:athleteiq/models/athlete.dart';
import 'package:athleteiq/models/checkin.dart';
import 'package:athleteiq/utils/athlete_data_completeness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AthleteProfile athlete({String tier = 'tier2'}) => AthleteProfile(
        uid: 'a1',
        name: 'Alex',
        createdAt: DateTime(2026, 8, 1),
        deviceTier: tier,
        deviceSetupCompleted: true,
        activeDevice: 'Health Connect',
      );

  CheckIn checkIn({double? hrv, double? rhr}) => CheckIn(
        id: '2026-08-15',
        date: DateTime(2026, 8, 15),
        fatigueScore: 3,
        hrv: hrv,
        restingHeartRate: rhr,
        sleepHours: 7.2,
        source: 'wearable',
      );

  test('Tier 2 Android flags missing HRV without inventing a value', () {
    final info = AthleteDataCompleteness.analyze(
      athlete(),
      [checkIn(rhr: 54)],
    );
    expect(info.tierLabel, 'Tier 2 · Partial wearable');
    expect(info.tierSummary, contains('Health Connect'));
    expect(info.missing, contains('HRV not available for this athlete'));
    expect(info.missing, isNot(contains('Resting heart rate not syncing')));
  });

  test('Tier 2 does not claim HRV is missing when a sample exists', () {
    final info = AthleteDataCompleteness.analyze(
      athlete(),
      [checkIn(hrv: 62, rhr: 54)],
    );
    expect(info.missing, isNot(contains('HRV not available for this athlete')));
  });

  test('Tier 1 still expects HRV', () {
    final info = AthleteDataCompleteness.analyze(
      athlete(tier: 'tier1'),
      [checkIn(rhr: 50)],
    );
    expect(info.tierLabel, 'Tier 1 · Full biometrics');
    expect(info.missing, contains('HRV not available for this athlete'));
  });
}
