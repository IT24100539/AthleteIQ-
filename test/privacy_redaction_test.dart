import 'package:athleteiq/models/checkin.dart';
import 'package:athleteiq/models/privacy_settings.dart';
import 'package:athleteiq/models/risk_result.dart';
import 'package:athleteiq/models/weekly_report.dart';
import 'package:athleteiq/utils/privacy_redaction.dart';
import 'package:athleteiq/utils/risk_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final checkIn = CheckIn(
    id: '2026-08-15',
    date: DateTime(2026, 8, 15),
    sessionDurationMinutes: 45,
    rpe: 6,
    fatigueScore: 4,
    sleepHours: 7.5,
    restingHeartRate: 52,
    hrv: 68,
    soreness: 'Left knee',
  );

  RiskResult risk() => RiskResult(
        riskLevel: 'HIGH',
        confidence: 'Medium (HRV available)',
        reason: 'ACWR 1.62 with HRV drop and fatigue 4',
        acwr: 1.62,
        trainingLoad7d: 400,
        trainingLoad28dAvg: 250,
        recoveryTrend: 'worsening',
        performancePrediction: 'DECLINING',
        recommendation: 'Reduce intensity',
        recommendationStatus: 'pending',
        calculatedAt: DateTime(2026, 8, 15),
        fatiguePersistent: true,
        avgFatigue7d: 4.2,
      );

  test('defaults are fully shared', () {
    expect(PrivacySettings.fromMap(null).allShared, isTrue);
    expect(PrivacySettings.fromMap({}).wearableData, isTrue);
  });

  test('redactCheckInForCoach strips wearable, load, fatigue, and soreness', () {
    final hidden = redactCheckInForCoach(
      checkIn,
      const PrivacySettings(
        wearableData: false,
        trainingLogs: false,
        injuryHistory: false,
        dailyFatigueCheckIn: false,
      ),
    );
    expect(hidden.sessionDurationMinutes, isNull);
    expect(hidden.rpe, isNull);
    expect(hidden.trainingLoad, isNull);
    expect(hidden.fatigueScore, 0);
    expect(hidden.sleepHours, isNull);
    expect(hidden.restingHeartRate, isNull);
    expect(hidden.hrv, isNull);
    expect(hidden.soreness, isNull);
  });

  test('redactCheckInForCoach keeps shared categories', () {
    final kept = redactCheckInForCoach(
      checkIn,
      const PrivacySettings(wearableData: false),
    );
    expect(kept.sessionDurationMinutes, 45);
    expect(kept.fatigueScore, 4);
    expect(kept.sleepHours, isNull);
    expect(kept.hrv, isNull);
  });

  test('redactRiskResultForCoach hides load numbers and mixed prose', () {
    final hidden = redactRiskResultForCoach(
      risk(),
      const PrivacySettings(trainingLogs: false),
    );
    expect(hidden.acwr, 0);
    expect(hidden.trainingLoad7d, 0);
    expect(hidden.riskLevel, 'HIGH');
    expect(hidden.recommendation, 'Reduce intensity');
    expect(hidden.reason, contains('not shared'));
    expect(hidden.avgFatigue7d, 4.2);
  });

  test('redactWeeklyReportForCoach drops sleep/fatigue/load and narrative', () {
    const report = WeeklyReport(
      weekStart: '2026-08-10',
      weekEnd: '2026-08-16',
      weekLabel: 'Aug 10–16',
      sessionsCompleted: 4,
      restDays: 3,
      checkInsLogged: 7,
      totalTrainingLoad: 900,
      avgSleepHours: 7.2,
      avgFatigue: 3.5,
      peakAcwr: 1.4,
      endAcwr: 1.2,
      coachAdjustments: 1,
      riskLevel: 'MEDIUM',
      recoveryTrend: 'stable',
      dailyLoads: [WeeklyDailyLoad(date: '2026-08-10', load: 200, fatigue: 3)],
      narrative: 'Sleep was 7.2h and load spiked.',
      narrativeSource: 'llm',
    );
    final hidden = redactWeeklyReportForCoach(
      report,
      const PrivacySettings(wearableData: false, trainingLogs: false),
    );
    expect(hidden.avgSleepHours, isNull);
    expect(hidden.totalTrainingLoad, 0);
    expect(hidden.peakAcwr, isNull);
    expect(hidden.avgFatigue, 3.5);
    expect(hidden.narrative, contains('not shared'));
    expect(hidden.dailyLoads.first.load, 0);
    expect(hidden.dailyLoads.first.fatigue, 3);
  });

  test('reconstructRiskHistory does not invent ACWR from redacted loads', () {
    final redacted = List.generate(
      6,
      (i) => redactCheckInForCoach(
        CheckIn(
          id: '$i',
          date: DateTime(2026, 8, 10 + i),
          sessionDurationMinutes: 40,
          rpe: 5,
          fatigueScore: 3,
        ),
        const PrivacySettings(trainingLogs: false),
      ),
    );
    expect(reconstructRiskHistory(redacted), isEmpty);
  });

  test('pain alerts are hidden when injury history is off', () {
    const p = PrivacySettings(injuryHistory: false);
    expect(p.allowsCoachAlertType('pain'), isFalse);
    expect(p.allowsCoachAlertType('missed_checkin'), isTrue);
    expect(p.allowsCoachAlertType('sync_failure'), isTrue);
  });
}
