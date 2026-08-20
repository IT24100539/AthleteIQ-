import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../models/checkin.dart';
import '../models/risk_result.dart';

class PerformanceTip {
  final IconData icon;
  final String text;

  const PerformanceTip({required this.icon, required this.text});
}

/// Short, grounded tips from the athlete's sport, risk read, and recent check-ins.
/// Returns empty when there is not enough data — never wireframe placeholder copy.
List<PerformanceTip> buildPerformanceTips({
  AthleteProfile? profile,
  RiskResult? result,
  List<CheckIn> checkIns = const [],
}) {
  if (result == null) return const [];

  final tips = <PerformanceTip>[];
  final sportLabel = (profile?.sportsLabel ?? '').trim().isNotEmpty
      ? profile!.sportsLabel
      : _sportGroupLabel(profile?.sportGroup ?? SportGroup.other);

  switch (result.recoveryTrend.toLowerCase()) {
    case 'worsening':
      tips.add(PerformanceTip(
        icon: Icons.trending_down,
        text:
            'Recovery trend is worsening on your latest read. Ease up before the next $sportLabel session.',
      ));
      break;
    case 'improving':
      tips.add(PerformanceTip(
        icon: Icons.trending_up,
        text:
            'Recovery is improving. Stay consistent with your $sportLabel plan.',
      ));
      break;
    default:
      tips.add(PerformanceTip(
        icon: Icons.horizontal_rule,
        text: 'Recovery trend is stable — keep logging daily check-ins for $sportLabel.',
      ));
  }

  if (result.acwr > 1.5) {
    tips.add(PerformanceTip(
      icon: Icons.warning_amber_rounded,
      text:
          'ACWR is ${result.acwr.toStringAsFixed(2)} (above 1.5). Recent load is spiking versus your baseline — talk to your coach before adding volume.',
    ));
  } else if (result.acwr > 1.3) {
    tips.add(PerformanceTip(
      icon: Icons.fitness_center_outlined,
      text:
          'ACWR is ${result.acwr.toStringAsFixed(2)} — load is climbing. A lighter $sportLabel session may fit better this week.',
    ));
  }

  if (result.performancePrediction.toUpperCase() == 'DECLINING') {
    tips.add(PerformanceTip(
      icon: Icons.speed,
      text:
          '${result.performanceAxisLabel} reads ${result.performanceDisplay} — fatigue is outpacing fitness on your logged load.',
    ));
  } else if (result.performancePrediction.toUpperCase() == 'GOOD') {
    tips.add(PerformanceTip(
      icon: Icons.check_circle_outline,
      text:
          '${result.performanceAxisLabel} is ${result.performanceDisplay} — your recent load and recovery line up for $sportLabel.',
    ));
  }

  if (result.fatiguePersistent) {
    tips.add(PerformanceTip(
      icon: Icons.battery_alert_outlined,
      text:
          'Fatigue has been high on your last several check-ins. Prioritize rest and sleep before hard $sportLabel work.',
    ));
  } else if (result.avgFatigue7d != null && result.avgFatigue7d! >= 3.5) {
    tips.add(PerformanceTip(
      icon: Icons.battery_3_bar,
      text:
          '7-day average fatigue is ${result.avgFatigue7d!.toStringAsFixed(1)}/5 — watch session intensity this week.',
    ));
  }

  final sleepTip = _sleepTipFromCheckIns(checkIns);
  if (sleepTip != null) tips.add(sleepTip);

  if (result.performanceReasoningLLM != null &&
      result.performanceReasoningLLM!.trim().isNotEmpty) {
    tips.add(PerformanceTip(
      icon: Icons.psychology_outlined,
      text: result.performanceReasoningLLM!.trim(),
    ));
  }

  // Dedupe similar text and cap length for the home-style cards.
  final seen = <String>{};
  final unique = <PerformanceTip>[];
  for (final tip in tips) {
    final key = tip.text.trim();
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    unique.add(tip);
    if (unique.length >= 4) break;
  }
  return unique;
}

PerformanceTip? _sleepTipFromCheckIns(List<CheckIn> checkIns) {
  final withSleep = checkIns
      .where((c) => c.sleepHours != null && c.sleepHours! > 0)
      .take(7)
      .toList();
  if (withSleep.isEmpty) return null;

  final avg = withSleep.map((c) => c.sleepHours!).reduce((a, b) => a + b) /
      withSleep.length;

  if (avg < 7.0) {
    return PerformanceTip(
      icon: Icons.bedtime_outlined,
      text:
          'Sleep averaged ${avg.toStringAsFixed(1)}h over your last ${withSleep.length} logged nights — recovery for training may be limited.',
    );
  }
  if (withSleep.length >= 4) {
    return PerformanceTip(
      icon: Icons.bedtime_outlined,
      text:
          'Sleep is averaging ${avg.toStringAsFixed(1)}h on recent check-ins — keep that up for recovery.',
    );
  }
  return null;
}

String _sportGroupLabel(SportGroup group) {
  switch (group) {
    case SportGroup.endurance:
      return 'endurance training';
    case SportGroup.teamContact:
      return 'team sport';
    case SportGroup.strengthPower:
      return 'strength training';
    case SportGroup.skillPrecision:
      return 'skill sport';
    case SportGroup.combat:
      return 'combat training';
    case SportGroup.other:
      return 'training';
  }
}
