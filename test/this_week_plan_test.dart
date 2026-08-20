import 'package:flutter_test/flutter_test.dart';
import 'package:athleteiq/models/checkin.dart';
import 'package:athleteiq/models/risk_result.dart';
import 'package:athleteiq/utils/this_week_plan.dart';

void main() {
  final monday = DateTime(2026, 8, 10); // Monday
  final wednesday = DateTime(2026, 8, 12);

  RiskResult risk({
    String status = 'approved',
    String rec = 'Keep today easy — reduce volume.',
  }) {
    return RiskResult(
      riskLevel: 'LOW',
      confidence: 'Medium',
      reason: 'Stable load',
      acwr: 1.0,
      trainingLoad7d: 100,
      trainingLoad28dAvg: 100,
      recoveryTrend: 'stable',
      performancePrediction: 'AVERAGE',
      recommendation: rec,
      recommendationStatus: status,
      calculatedAt: monday,
    );
  }

  CheckIn checkIn(DateTime date, {int mins = 40, int rpe = 5}) {
    return CheckIn(
      id: date.toIso8601String(),
      date: date,
      sessionDurationMinutes: mins,
      rpe: rpe,
      fatigueScore: 3,
    );
  }

  test('empty week with no approved rec is not real data', () {
    final days = buildThisWeekDays(now: wednesday, checkIns: const [], result: null);
    expect(days.length, 7);
    expect(thisWeekHasRealData(days), isFalse);
    expect(days[0].dayLabel, 'Mon');
    expect(days[0].kind, ThisWeekDayKind.notLogged);
    expect(days[0].activity, 'Not logged');
    expect(days[2].kind, ThisWeekDayKind.notLogged); // today, no rec
    expect(days[3].kind, ThisWeekDayKind.upcoming);
    expect(days[3].activity, 'No plan yet');
  });

  test('does not invent Light run / Rest for unlogged days', () {
    final days = buildThisWeekDays(now: wednesday, checkIns: const [], result: null);
    for (final d in days) {
      expect(d.activity, isNot(contains('Light run')));
      expect(d.activity, isNot(contains('Normal session')));
      if (d.kind != ThisWeekDayKind.rest) {
        expect(d.activity == 'Rest', isFalse);
      }
    }
  });

  test('logged rest and sessions come from check-ins', () {
    final days = buildThisWeekDays(
      now: wednesday,
      checkIns: [
        checkIn(monday, mins: 0, rpe: 0),
        checkIn(DateTime(2026, 8, 11), mins: 45, rpe: 4),
      ],
      result: null,
    );
    expect(thisWeekHasRealData(days), isTrue);
    expect(days[0].kind, ThisWeekDayKind.rest);
    expect(days[0].activity, 'Rest');
    expect(days[1].kind, ThisWeekDayKind.trained);
    expect(days[1].activity, contains('Moderate session'));
    expect(days[1].activity, contains('45 min'));
  });

  test('today uses approved recommendation when not yet logged', () {
    final days = buildThisWeekDays(
      now: wednesday,
      checkIns: const [],
      result: risk(),
    );
    expect(thisWeekHasRealData(days), isTrue);
    expect(days[2].kind, ThisWeekDayKind.plan);
    expect(days[2].activity, contains('Keep today easy'));
    expect(days[0].kind, ThisWeekDayKind.notLogged);
  });

  test('pending recommendation is hidden from this week', () {
    final days = buildThisWeekDays(
      now: wednesday,
      checkIns: const [],
      result: risk(status: 'pending'),
    );
    expect(thisWeekHasRealData(days), isFalse);
    expect(days[2].kind, ThisWeekDayKind.notLogged);
    expect(days[2].activity, isNot(contains('Keep today easy')));
  });

  test('modified recommendation is shown like approved', () {
    final days = buildThisWeekDays(
      now: wednesday,
      checkIns: const [],
      result: risk(status: 'modified', rec: 'Swim recovery 30 min'),
    );
    expect(days[2].kind, ThisWeekDayKind.plan);
    expect(days[2].activity, contains('Swim recovery'));
  });

  test('logged check-in wins over recommendation on that day', () {
    final days = buildThisWeekDays(
      now: wednesday,
      checkIns: [checkIn(wednesday, mins: 30, rpe: 8)],
      result: risk(rec: 'Rest day'),
    );
    expect(days[2].kind, ThisWeekDayKind.trained);
    expect(days[2].activity, contains('Hard session'));
  });
}
