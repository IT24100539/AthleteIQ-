import 'package:athleteiq/models/risk_result.dart';
import 'package:athleteiq/utils/approval_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RiskResult risk({
    String status = 'pending',
    String rec = 'Cut volume 20%',
    String reason = 'ACWR 1.6 plus orchestrator note',
  }) {
    return RiskResult(
      riskLevel: 'HIGH',
      confidence: 'Medium',
      reason: reason,
      acwr: 1.6,
      trainingLoad7d: 400,
      trainingLoad28dAvg: 250,
      recoveryTrend: 'worsening',
      performancePrediction: 'DECLINING',
      recommendation: rec,
      recommendationStatus: status,
      calculatedAt: DateTime(2026, 8, 15),
      riskLevelReasoningLLM: 'LLM risk prose',
      performanceReasoningLLM: 'LLM performance prose',
      gradedOptions: const [],
      researchNote: 'citation note',
      ruleBasedRecommendation: 'Rule rec',
    );
  }

  test('only approved and modified are released to the athlete', () {
    expect(recommendationReleasedToAthlete(null), isFalse);
    expect(recommendationReleasedToAthlete('pending'), isFalse);
    expect(recommendationReleasedToAthlete('rejected'), isFalse);
    expect(recommendationReleasedToAthlete('approved'), isTrue);
    expect(recommendationReleasedToAthlete('modified'), isTrue);
    expect(recommendationReleasedToAthlete('APPROVED'), isTrue);
    expect(risk(status: 'pending').isReleasedToAthlete, isFalse);
    expect(risk(status: 'modified').isReleasedToAthlete, isTrue);
  });

  test('redactUnreleasedRecommendation keeps scores and strips rec prose', () {
    final redacted = redactUnreleasedRecommendation(risk());
    expect(redacted.acwr, 1.6);
    expect(redacted.riskLevel, 'HIGH');
    expect(redacted.recommendationStatus, 'pending');
    expect(redacted.recommendation, isEmpty);
    expect(redacted.reason, isEmpty);
    expect(redacted.riskLevelReasoningLLM, isNull);
    expect(redacted.performanceReasoningLLM, isNull);
    expect(redacted.researchNote, isNull);
    expect(redacted.ruleBasedRecommendation, isNull);
  });

  test('redactUnreleasedRecommendation is a no-op once released', () {
    final approved = risk(status: 'approved');
    expect(identical(redactUnreleasedRecommendation(approved), approved), isTrue);
    final modified = risk(status: 'modified');
    expect(redactUnreleasedRecommendation(modified).recommendation, 'Cut volume 20%');
  });
}
