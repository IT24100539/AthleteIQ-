import 'dart:math' as math;

import '../models/checkin.dart';
import '../models/risk_result.dart';

/// Dart port of `functions/src/calculations.ts` + the performance/ACWR
/// branches of `assessRisk()` so chart screens can reconstruct a trend
/// when dated `riskResults/{yyyy-MM-dd}` snapshots are still sparse.
class _Daily {
  final String date;
  final double trainingLoad;
  final double? sleepHours;
  final double? restingHeartRate;
  final double? hrv;
  final int fatigueScore;

  const _Daily({
    required this.date,
    required this.trainingLoad,
    required this.sleepHours,
    required this.restingHeartRate,
    required this.hrv,
    required this.fatigueScore,
  });
}

List<RiskHistoryPoint> reconstructRiskHistory(List<CheckIn> checkIns) {
  if (checkIns.length < 5) return [];
  // Redacted coach views null out duration/RPE. Don't rebuild ACWR from zeros.
  final hasSharedLoad = checkIns.any(
    (c) => c.sessionDurationMinutes != null && c.rpe != null,
  );
  if (!hasSharedLoad) return [];

  final byDate = <String, _Daily>{};
  for (final c in checkIns) {
    final key = _dateKey(c.date);
    byDate[key] = _Daily(
      date: key,
      trainingLoad: c.trainingLoad ?? 0,
      sleepHours: c.sleepHours,
      restingHeartRate: c.restingHeartRate,
      hrv: c.hrv,
      fatigueScore: c.fatigueScore,
    );
  }

  final days = byDate.keys.toList()..sort();
  final points = <RiskHistoryPoint>[];

  for (var i = 0; i < days.length; i++) {
    final windowDays = days.sublist(0, i + 1);
    if (windowDays.length < 5) continue;
    final recentFirst = windowDays.reversed
        .take(35)
        .map((d) => byDate[d]!)
        .toList();
    points.add(_assess(recentFirst));
  }

  return points;
}

RiskHistoryPoint _assess(List<_Daily> recentFirst) {
  final acute7 = _sumLoad(recentFirst, 7);
  final chronicAvgWeekly = _sumLoad(recentFirst, 28) / 4;
  final acwr = chronicAvgWeekly > 0 ? acute7 / chronicAvgWeekly : 1.0;
  final recovery = _recoveryTrend(recentFirst);
  final fatiguePersistent = _fatiguePersistent(recentFirst);
  final oldestFirst = recentFirst.reversed.toList();
  final index = _performanceIndex(oldestFirst);

  String band;
  if (index > 0 && recovery != 'worsening') {
    band = 'GOOD';
  } else if (index < 0 || fatiguePersistent) {
    band = 'DECLINING';
  } else {
    band = 'AVERAGE';
  }

  String riskLevel;
  if (acwr > 1.5 && recovery == 'worsening' && fatiguePersistent) {
    riskLevel = 'HIGH';
  } else if (acwr >= 0.8 && acwr <= 1.3 && recovery == 'stable') {
    riskLevel = 'LOW';
  } else {
    riskLevel = 'MEDIUM';
  }

  final last7 = recentFirst.take(7).toList();
  final avgFatigue =
      last7.fold<double>(0, (s, e) => s + e.fatigueScore) / last7.length;

  return RiskHistoryPoint(
    id: recentFirst.first.date,
    date: DateTime.parse(recentFirst.first.date),
    acwr: acwr,
    performancePrediction: band,
    recoveryTrend: recovery,
    riskLevel: riskLevel,
    trainingLoad7d: acute7,
    trainingLoad28dAvg: chronicAvgWeekly,
    avgFatigue7d: avgFatigue,
    fatiguePersistent: fatiguePersistent,
  );
}

double _sumLoad(List<_Daily> entries, int days) {
  return entries.take(days).fold<double>(0, (s, e) => s + e.trainingLoad);
}

double _performanceIndex(List<_Daily> oldestFirst) {
  const fitnessTau = 42.0;
  const fatigueTau = 7.0;
  var fitness = 0.0;
  var fatigue = 0.0;
  for (final e in oldestFirst) {
    fitness = fitness * math.exp(-1 / fitnessTau) + e.trainingLoad;
    fatigue = fatigue * math.exp(-1 / fatigueTau) + e.trainingLoad;
  }
  return fitness - fatigue;
}

bool _fatiguePersistent(List<_Daily> recentFirst) {
  final last4 = recentFirst.take(4).toList();
  if (last4.length < 4) return false;
  return last4.every((e) => e.fatigueScore >= 4);
}

String _recoveryTrend(List<_Daily> recentFirst) {
  final last7 = recentFirst.take(7).toList();
  final prev7 = recentFirst.skip(7).take(7).toList();
  final lastHrv = _avg(last7.map((e) => e.hrv).whereType<double>());
  final prevHrv = _avg(prev7.map((e) => e.hrv).whereType<double>());
  if (lastHrv != null && prevHrv != null && prevHrv != 0) {
    final change = (lastHrv - prevHrv) / prevHrv;
    if (change > 0.05) return 'improving';
    if (change < -0.05) return 'worsening';
    return 'stable';
  }

  var worse = 0;
  var better = 0;
  final rhrRecent = _avg(last7.map((e) => e.restingHeartRate).whereType<double>());
  final rhrPrior = _avg(prev7.map((e) => e.restingHeartRate).whereType<double>());
  if (rhrRecent != null && rhrPrior != null) {
    if (rhrRecent > rhrPrior * 1.03) {
      worse++;
    } else if (rhrRecent < rhrPrior * 0.97) {
      better++;
    }
  }

  final sleepRecent = _avg(last7.map((e) => e.sleepHours).whereType<double>());
  final sleepPrior = _avg(prev7.map((e) => e.sleepHours).whereType<double>());
  if (sleepRecent != null && sleepPrior != null) {
    if (sleepRecent < sleepPrior - 0.5) {
      worse++;
    } else if (sleepRecent > sleepPrior + 0.5) {
      better++;
    }
  }

  final fatigueRecent = _avg(last7.map((e) => e.fatigueScore.toDouble()));
  final fatiguePrior = _avg(prev7.map((e) => e.fatigueScore.toDouble()));
  if (fatiguePrior != null && fatigueRecent != null) {
    if (fatigueRecent > fatiguePrior + 0.4) {
      worse++;
    } else if (fatigueRecent < fatiguePrior - 0.4) {
      better++;
    }
  }

  if (worse > better) return 'worsening';
  if (better > worse) return 'improving';
  return 'stable';
}

double? _avg(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) return null;
  return list.reduce((a, b) => a + b) / list.length;
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
