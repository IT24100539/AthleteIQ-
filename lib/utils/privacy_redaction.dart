import '../models/checkin.dart';
import '../models/privacy_settings.dart';
import '../models/risk_result.dart';
import '../models/weekly_report.dart';

const kPrivacyNotShared = PrivacySettings.notShared;

String sharedOrHidden(bool allowed, String value) =>
    allowed ? value : kPrivacyNotShared;

/// Strip check-in fields the athlete has not shared with their coach.
/// Fatigue uses 0 as a withheld sentinel (valid scores are 1–5).
CheckIn redactCheckInForCoach(CheckIn checkIn, PrivacySettings privacy) {
  return CheckIn(
    id: checkIn.id,
    date: checkIn.date,
    sessionDurationMinutes:
        privacy.trainingLogs ? checkIn.sessionDurationMinutes : null,
    rpe: privacy.trainingLogs ? checkIn.rpe : null,
    fatigueScore: privacy.dailyFatigueCheckIn ? checkIn.fatigueScore : 0,
    sleepHours: privacy.wearableData ? checkIn.sleepHours : null,
    restingHeartRate: privacy.wearableData ? checkIn.restingHeartRate : null,
    hrv: privacy.wearableData ? checkIn.hrv : null,
    soreness: privacy.injuryHistory ? checkIn.soreness : null,
    source: checkIn.source,
  );
}

List<CheckIn> redactCheckInsForCoach(
  List<CheckIn> checkIns,
  PrivacySettings privacy,
) {
  if (privacy.allShared) return checkIns;
  return checkIns.map((c) => redactCheckInForCoach(c, privacy)).toList();
}

/// Zero / drop aggregates that would leak withheld check-in inputs.
RiskResult redactRiskResultForCoach(
  RiskResult result,
  PrivacySettings privacy,
) {
  if (privacy.allShared) return result;
  final shareLoad = privacy.trainingLogs;
  final shareWearable = privacy.wearableData;
  final shareFatigue = privacy.dailyFatigueCheckIn;
  final shareProse = shareLoad && shareWearable && shareFatigue;

  return RiskResult(
    riskLevel: result.riskLevel,
    confidence: shareWearable ? result.confidence : kPrivacyNotShared,
    reason: shareProse
        ? result.reason
        : 'Some inputs are not shared with you, so the written explanation is hidden.',
    acwr: shareLoad ? result.acwr : 0,
    trainingLoad7d: shareLoad ? result.trainingLoad7d : 0,
    trainingLoad28dAvg: shareLoad ? result.trainingLoad28dAvg : 0,
    recoveryTrend: shareWearable ? result.recoveryTrend : kPrivacyNotShared,
    performancePrediction: shareLoad ? result.performancePrediction : 'AVERAGE',
    performanceFrame: shareLoad ? result.performanceFrame : kPrivacyNotShared,
    performanceFrameAxis: result.performanceFrameAxis,
    riskLevelReasoningLLM: shareProse ? result.riskLevelReasoningLLM : null,
    riskLevelPatternFlag: shareProse ? result.riskLevelPatternFlag : null,
    performanceReasoningLLM: shareProse ? result.performanceReasoningLLM : null,
    recommendation: result.recommendation,
    recommendationStatus: result.recommendationStatus,
    gradedOptions: result.gradedOptions,
    researchNote: shareProse ? result.researchNote : null,
    researchCitations: shareProse ? result.researchCitations : const [],
    calculatedAt: result.calculatedAt,
    fatiguePersistent: shareFatigue && result.fatiguePersistent,
    avgFatigue7d: shareFatigue ? result.avgFatigue7d : null,
    orchestratorConflict: shareProse ? result.orchestratorConflict : null,
    orchestratorSafetyOverride: result.orchestratorSafetyOverride,
    orchestratorSource: result.orchestratorSource,
    ruleBasedRecommendation: shareProse ? result.ruleBasedRecommendation : null,
    ruleBasedOrchestratorNote: shareProse ? result.ruleBasedOrchestratorNote : null,
    orchestratorAgreedWithRules: result.orchestratorAgreedWithRules,
  );
}

List<RiskHistoryPoint> redactRiskHistoryForCoach(
  List<RiskHistoryPoint> points,
  PrivacySettings privacy,
) {
  if (!privacy.trainingLogs) return const [];
  if (privacy.dailyFatigueCheckIn && privacy.wearableData) return points;
  return points
      .map(
        (p) => RiskHistoryPoint(
          id: p.id,
          date: p.date,
          acwr: p.acwr,
          performancePrediction: p.performancePrediction,
          performanceFrame: p.performanceFrame,
          performanceFrameAxis: p.performanceFrameAxis,
          recoveryTrend:
              privacy.wearableData ? p.recoveryTrend : kPrivacyNotShared,
          riskLevel: p.riskLevel,
          trainingLoad7d: p.trainingLoad7d,
          trainingLoad28dAvg: p.trainingLoad28dAvg,
          avgFatigue7d: privacy.dailyFatigueCheckIn ? p.avgFatigue7d : null,
          fatiguePersistent: privacy.dailyFatigueCheckIn && p.fatiguePersistent,
        ),
      )
      .toList();
}

WeeklyReport redactWeeklyReportForCoach(
  WeeklyReport report,
  PrivacySettings privacy,
) {
  if (privacy.allShared) return report;
  final shareLoad = privacy.trainingLogs;
  final shareSleep = privacy.wearableData;
  final shareFatigue = privacy.dailyFatigueCheckIn;

  return WeeklyReport(
    weekStart: report.weekStart,
    weekEnd: report.weekEnd,
    weekLabel: report.weekLabel,
    sessionsCompleted: shareLoad ? report.sessionsCompleted : 0,
    restDays: shareLoad ? report.restDays : 0,
    checkInsLogged: report.checkInsLogged,
    totalTrainingLoad: shareLoad ? report.totalTrainingLoad : 0,
    avgSleepHours: shareSleep ? report.avgSleepHours : null,
    avgFatigue: shareFatigue ? report.avgFatigue : null,
    peakAcwr: shareLoad ? report.peakAcwr : null,
    endAcwr: shareLoad ? report.endAcwr : null,
    coachAdjustments: report.coachAdjustments,
    riskLevel: report.riskLevel,
    recoveryTrend: shareSleep ? report.recoveryTrend : null,
    dailyLoads: [
      for (final d in report.dailyLoads)
        WeeklyDailyLoad(
          date: d.date,
          load: shareLoad ? d.load : 0,
          fatigue: shareFatigue ? d.fatigue : 0,
        ),
    ],
    narrative: privacy.allShared
        ? report.narrative
        : 'Some metrics this week are not shared with you. Rows below omit withheld fields.',
    narrativeSource: 'rules',
  );
}
