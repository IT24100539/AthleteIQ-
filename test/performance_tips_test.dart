import 'package:flutter_test/flutter_test.dart';
import 'package:athleteiq/models/athlete.dart';
import 'package:athleteiq/models/checkin.dart';
import 'package:athleteiq/models/risk_result.dart';
import 'package:athleteiq/utils/performance_tips.dart';

void main() {
  RiskResult baseResult({
    String recovery = 'worsening',
    double acwr = 1.55,
    String perf = 'DECLINING',
  }) {
    return RiskResult(
      riskLevel: 'MEDIUM',
      confidence: 'Medium',
      reason: 'Load spike with rising fatigue.',
      acwr: acwr,
      trainingLoad7d: 400,
      trainingLoad28dAvg: 250,
      recoveryTrend: recovery,
      performancePrediction: perf,
      performanceFrame: 'Building fatigue',
      performanceFrameAxis: 'Race readiness',
      recommendation: 'Reduce volume',
      calculatedAt: DateTime.now(),
      fatiguePersistent: true,
      avgFatigue7d: 4.2,
    );
  }

  test('tips use actual metrics not static Tuesday copy', () {
    final tips = buildPerformanceTips(
      profile: AthleteProfile(
        uid: 'a',
        name: 'Test',
        sport: 'Running / Athletics',
        sportGroup: SportGroup.endurance,
        createdAt: DateTime.now(),
      ),
      result: baseResult(),
      checkIns: const [],
    );

    expect(tips, isNotEmpty);
    for (final tip in tips) {
      expect(tip.text, isNot(contains('Tuesday')));
      expect(tip.text, isNot(contains('competition day')));
      expect(tip.text, isNot(contains('hydration and light dynamic stretching')));
    }
    expect(
      tips.any((t) => t.text.contains('1.55') || t.text.contains('ACWR')),
      isTrue,
    );
    expect(
      tips.any((t) => t.text.contains('Running') || t.text.contains('endurance')),
      isTrue,
    );
  });

  test('sleep tip uses logged check-in averages', () {
    final tips = buildPerformanceTips(
      result: baseResult(acwr: 1.0, recovery: 'stable', perf: 'AVERAGE'),
      checkIns: [
        CheckIn(
          id: '1',
          date: DateTime.now(),
          fatigueScore: 3,
          sleepHours: 5.5,
        ),
        CheckIn(
          id: '2',
          date: DateTime.now().subtract(const Duration(days: 1)),
          fatigueScore: 3,
          sleepHours: 6.0,
        ),
      ],
    );

    expect(tips.any((t) => t.text.contains('5.8') || t.text.contains('5.5')), isTrue);
  });

  test('empty when no risk result', () {
    expect(buildPerformanceTips(result: null), isEmpty);
  });
}
