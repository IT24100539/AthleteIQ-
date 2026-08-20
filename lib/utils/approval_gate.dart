import '../models/risk_result.dart';

/// Coach "Send to athlete" writes `modified`; Approve writes `approved`.
/// Anything else (`pending`, `rejected`, missing) stays behind the gate.
bool recommendationReleasedToAthlete(String? status) {
  final s = (status ?? 'pending').toLowerCase();
  return s == 'approved' || s == 'modified';
}

/// Strip recommendation prose so an athlete-facing stream cannot leak a
/// pending / rejected plan even if a screen forgets the UI check.
RiskResult redactUnreleasedRecommendation(RiskResult result) {
  if (recommendationReleasedToAthlete(result.recommendationStatus)) {
    return result;
  }
  return RiskResult(
    riskLevel: result.riskLevel,
    confidence: result.confidence,
    reason: '',
    acwr: result.acwr,
    trainingLoad7d: result.trainingLoad7d,
    trainingLoad28dAvg: result.trainingLoad28dAvg,
    recoveryTrend: result.recoveryTrend,
    performancePrediction: result.performancePrediction,
    performanceFrame: result.performanceFrame,
    performanceFrameAxis: result.performanceFrameAxis,
    riskLevelPatternFlag: result.riskLevelPatternFlag,
    recommendation: '',
    recommendationStatus: result.recommendationStatus ?? 'pending',
    calculatedAt: result.calculatedAt,
    fatiguePersistent: result.fatiguePersistent,
    avgFatigue7d: result.avgFatigue7d,
    orchestratorSafetyOverride: result.orchestratorSafetyOverride,
    orchestratorSource: result.orchestratorSource,
    orchestratorAgreedWithRules: result.orchestratorAgreedWithRules,
  );
}
