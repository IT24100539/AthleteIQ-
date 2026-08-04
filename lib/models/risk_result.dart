/// Mirrors the shape written by the `recalculateRisk` Cloud Function
/// (functions/src/index.ts) into athletes/{uid}/riskResults/latest.
class RiskResult {
  final String riskLevel; // LOW | MEDIUM | HIGH
  final String confidence; // e.g. "Medium (HRV not available)"
  final String reason; // plain-language explanation
  final double acwr;
  final double trainingLoad7d;
  final double trainingLoad28dAvg;
  final String recoveryTrend; // 'improving' | 'stable' | 'worsening'
  final String performancePrediction; // GOOD | AVERAGE | DECLINING
  final String recommendation;
  final String? recommendationStatus; // pending | approved | rejected | modified
  final DateTime calculatedAt;

  RiskResult({
    required this.riskLevel,
    required this.confidence,
    required this.reason,
    required this.acwr,
    required this.trainingLoad7d,
    required this.trainingLoad28dAvg,
    required this.recoveryTrend,
    required this.performancePrediction,
    required this.recommendation,
    this.recommendationStatus,
    required this.calculatedAt,
  });

  factory RiskResult.fromMap(Map<String, dynamic> map) => RiskResult(
        riskLevel: map['riskLevel'] ?? 'LOW',
        confidence: map['confidence'] ?? '',
        reason: map['reason'] ?? '',
        acwr: (map['acwr'] as num?)?.toDouble() ?? 0,
        trainingLoad7d: (map['trainingLoad7d'] as num?)?.toDouble() ?? 0,
        trainingLoad28dAvg: (map['trainingLoad28dAvg'] as num?)?.toDouble() ?? 0,
        recoveryTrend: map['recoveryTrend'] ?? 'stable',
        performancePrediction: map['performancePrediction'] ?? 'AVERAGE',
        recommendation: map['recommendation'] ?? '',
        recommendationStatus: map['recommendationStatus'],
        calculatedAt: DateTime.tryParse(map['calculatedAt'] ?? '') ?? DateTime.now(),
      );
}
